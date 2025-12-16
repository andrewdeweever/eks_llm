import os
import boto3
from openai import OpenAI
import faiss
import numpy as np
from langchain.text_splitter import RecursiveCharacterTextSplitter
from langchain_community.document_loaders import TextLoader, PyPDFLoader
from langchain_openai import OpenAIEmbeddings
import pickle
from io import BytesIO
import logging

# Set up logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Environment variables
S3_BUCKET = os.getenv("S3_BUCKET", "eks-llm-rag-documents-dev")
S3_PREFIX = os.getenv("S3_PREFIX", "documents/")
EMBEDDING_ENDPOINT = os.getenv("EMBEDDING_ENDPOINT", "http://vllm-router-service.vllm.svc.cluster.local:8000/v1")
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY", "dummy-key")  # vLLM doesn't require real key
INDEX_KEY = os.getenv("INDEX_KEY", "vector_index.faiss")
METADATA_KEY = os.getenv("METADATA_KEY", "metadata.pkl")
CHUNK_SIZE = int(os.getenv("CHUNK_SIZE", "500"))
CHUNK_OVERLAP = int(os.getenv("CHUNK_OVERLAP", "50"))
TOP_K = int(os.getenv("TOP_K", "5"))  # For retrieval, but used here for config

# Initialize clients
s3_client = boto3.client("s3")
embedding_client = OpenAI(
    base_url=EMBEDDING_ENDPOINT,
    api_key=OPENAI_API_KEY,
)

class S3RAGIngester:
    def __init__(self, bucket, prefix):
        self.bucket = bucket
        self.prefix = prefix
        self.embeddings = OpenAIEmbeddings(
            openai_api_key=OPENAI_API_KEY,
            openai_api_base=EMBEDDING_ENDPOINT,
            model="text-embedding-ada-002",  # vLLM uses OpenAI compat, adjust if needed
        )
        self.text_splitter = RecursiveCharacterTextSplitter(
            chunk_size=CHUNK_SIZE,
            chunk_overlap=CHUNK_OVERLAP,
        )
        self.documents = []
        self.metadatas = []

    def list_s3_objects(self):
        """List objects in S3 prefix."""
        objects = []
        paginator = s3_client.get_paginator("list_objects_v2")
        for page in paginator.paginate(Bucket=self.bucket, Prefix=self.prefix):
            if "Contents" in page:
                for obj in page["Contents"]:
                    if obj["Key"].endswith((".txt", ".pdf")):  # Support text and PDF
                        objects.append(obj["Key"])
        logger.info(f"Found {len(objects)} documents in S3.")
        return objects

    def load_document(self, key):
        """Load document from S3 based on extension."""
        response = s3_client.get_object(Bucket=self.bucket, Key=key)
        content = response["Body"].read().decode("utf-8")
        if key.endswith(".pdf"):
            # For PDF, we'd need to parse properly; simplified here
            from PyPDF2 import PdfReader
            reader = PdfReader(BytesIO(response["Body"].read()))
            content = "".join(page.extract_text() for page in reader.pages)
        return content

    def ingest_documents(self):
        """Ingest all documents: split, embed, build index."""
        keys = self.list_s3_objects()
        all_texts = []
        all_metadatas = []

        for key in keys:
            try:
                content = self.load_document(key)
                splits = self.text_splitter.split_text(content)
                for i, split in enumerate(splits):
                    all_texts.append(split)
                    all_metadatas.append({"source": key, "chunk": i})
                logger.info(f"Ingested {key}")
            except Exception as e:
                logger.error(f"Error ingesting {key}: {e}")

        if not all_texts:
            logger.warning("No texts to embed.")
            return None, None

        # Generate embeddings
        logger.info("Generating embeddings...")
        embeddings = self.embeddings.embed_documents(all_texts)

        # Build FAISS index
        dimension = len(embeddings[0])
        index = faiss.IndexFlatL2(dimension)
        index.add(np.array(embeddings).astype("float32"))

        self.documents = all_texts
        self.metadatas = all_metadatas

        logger.info(f"Built index with {len(all_texts)} chunks.")
        return index, all_metadatas

    def save_to_s3(self, index, metadatas):
        """Save FAISS index and metadata to S3."""
        # Save index
        index_bytes = BytesIO()
        faiss.write_index(index, index_bytes)
        index_bytes.seek(0)
        s3_client.put_object(
            Bucket=self.bucket,
            Key=INDEX_KEY,
            Body=index_bytes,
            ContentType="application/octet-stream",
        )

        # Save metadata
        metadata_bytes = BytesIO(pickle.dumps(metadatas))
        metadata_bytes.seek(0)
        s3_client.put_object(
            Bucket=self.bucket,
            Key=METADATA_KEY,
            Body=metadata_bytes,
            ContentType="application/python-pickled",
        )

        logger.info("Saved index and metadata to S3.")

def main():
    ingester = S3RAGIngester(S3_BUCKET, S3_PREFIX)
    index, metadatas = ingester.ingest_documents()
    if index is not None:
        ingester.save_to_s3(index, metadatas)
    else:
        logger.error("Ingestion failed.")

if __name__ == "__main__":
    main()