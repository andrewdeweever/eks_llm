import os
import boto3
import faiss
import numpy as np
import pickle
from io import BytesIO
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from openai import OpenAI
from typing import List, Optional
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="RAG Retrieval Service")

# Environment variables
S3_BUCKET = os.getenv("S3_BUCKET", "eks-llm-rag-documents-dev")
INDEX_KEY = os.getenv("INDEX_KEY", "vector_index.faiss")
METADATA_KEY = os.getenv("METADATA_KEY", "metadata.pkl")
EMBEDDING_ENDPOINT = os.getenv("EMBEDDING_ENDPOINT", "http://vllm-router-service.vllm.svc.cluster.local/v1")
LLM_ENDPOINT = os.getenv("LLM_ENDPOINT", "http://vllm-router-service.vllm.svc.cluster.local/v1")
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY", "dummy-key")
TOP_K = int(os.getenv("TOP_K", "5"))
MAX_TOKENS = int(os.getenv("MAX_TOKENS", "512"))
TEMPERATURE = float(os.getenv("TEMPERATURE", "0.7"))

# Clients
s3_client = boto3.client("s3")
embedding_client = OpenAI(base_url=EMBEDDING_ENDPOINT, api_key=OPENAI_API_KEY)
llm_client = OpenAI(base_url=LLM_ENDPOINT, api_key=OPENAI_API_KEY)

# Global variables for index and metadata
index = None
metadatas = None
documents = None  # Optional, if storing texts

class ChatRequest(BaseModel):
    model: str = "llama2-7b"  # Default to LLM model
    messages: List[dict]
    temperature: Optional[float] = TEMPERATURE
    max_tokens: Optional[int] = MAX_TOKENS
    top_k: Optional[int] = TOP_K

class EmbeddingRequest(BaseModel):
    input: str
    model: str = "text-embedding-ada-002"  # Compatible with vLLM

def load_index_from_s3():
    global index, metadatas, documents
    try:
        # Load index
        response = s3_client.get_object(Bucket=S3_BUCKET, Key=INDEX_KEY)
        index_bytes = BytesIO(response["Body"].read())
        index = faiss.read_index(index_bytes)

        # Load metadata
        response = s3_client.get_object(Bucket=S3_BUCKET, Key=METADATA_KEY)
        metadata_bytes = BytesIO(response["Body"].read())
        metadatas = pickle.loads(metadata_bytes.read())

        logger.info(f"Loaded index with {index.ntotal} vectors.")
    except Exception as e:
        logger.error(f"Error loading index: {e}")
        raise HTTPException(status_code=500, detail="Failed to load vector index")

# Load on startup
@app.on_event("startup")
async def startup_event():
    load_index_from_s3()

@app.post("/v1/embeddings")
async def create_embedding(request: EmbeddingRequest):
    try:
        response = embedding_client.embeddings.create(
            model=request.model,
            input=request.input
        )
        return response
    except Exception as e:
        logger.error(f"Embedding error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/v1/chat/completions")
async def rag_chat(request: ChatRequest):
    if index is None or metadatas is None:
        raise HTTPException(status_code=500, detail="Vector index not loaded")

    # Get the last user message as query
    query = next((msg["content"] for msg in reversed(request.messages) if msg["role"] == "user"), "")
    if not query:
        raise HTTPException(status_code=400, detail="No user message found")

    # Embed query
    embedding_response = embedding_client.embeddings.create(
        model="text-embedding-ada-002",
        input=query
    )
    query_embedding = np.array([embedding_response.data[0].embedding]).astype("float32")

    # Retrieve top-k
    distances, indices = index.search(query_embedding, request.top_k)
    retrieved_docs = [metadatas[i] for i in indices[0]]
    context = "\n".join([f"Source: {doc['source']}, Chunk: {doc['chunk']}: {documents[i] if documents else 'Text not stored'}" for i, doc in zip(indices[0], retrieved_docs)])

    # Build prompt with context
    system_prompt = "You are a helpful assistant. Use the following context to answer the question."
    full_prompt = f"{system_prompt}\n\nContext:\n{context}\n\nQuestion: {query}\nAnswer:"
    messages = [{"role": "system", "content": system_prompt}, {"role": "user", "content": full_prompt}]

    # Call LLM
    try:
        response = llm_client.chat.completions.create(
            model=request.model,
            messages=messages,
            temperature=request.temperature,
            max_tokens=request.max_tokens
        )
        return response
    except Exception as e:
        logger.error(f"LLM call error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)