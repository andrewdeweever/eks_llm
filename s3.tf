# S3 bucket for RAG documents and vector indexes
# This bucket stores raw documents (e.g., PDFs, text files) and FAISS index files for the vector store.
# Best practices: Enable versioning for recovery, server-side encryption with KMS, block public access.
# Assumptions: AWS provider configured; var.project_name and var.environment defined.
# To upload files: Use AWS CLI (aws s3 cp) or console; ensure IAM policies allow access from EKS pods.

resource "aws_s3_bucket" "rag_documents" {
  bucket = "${var.project_name}-rag-documents-${var.environment}" # e.g., eks-llm-rag-documents-dev; unique across AWS

  tags = {
    Name        = "${var.project_name}-rag-documents"
    Environment = var.environment
    ManagedBy   = "Terraform"
    Purpose     = "RAG knowledge base storage"
  }
}

# Enable versioning to protect against accidental deletions
resource "aws_s3_bucket_versioning" "rag_documents_versioning" {
  bucket = aws_s3_bucket.rag_documents.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Server-side encryption with AWS-managed KMS key (SSE-S3)
resource "aws_s3_bucket_server_side_encryption_configuration" "rag_documents_encryption" {
  bucket = aws_s3_bucket.rag_documents.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block public access for security
resource "aws_s3_bucket_public_access_block" "rag_documents_public_access" {
  bucket = aws_s3_bucket.rag_documents.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Optional: Lifecycle policy to transition old objects to cheaper storage (e.g., Glacier for archives)
# resource "aws_s3_bucket_lifecycle_configuration" "rag_documents_lifecycle" {
#   bucket = aws_s3_bucket.rag_documents.id
#
#   rule {
#     id     = "transition-to-ia-after-30-days"
#     status = "Enabled"
#
#     transition {
#       days          = 30
#       storage_class = "ONEZONE_IA"
#     }
#   }
# }

# Output the bucket name for reference (e.g., for ingestion scripts)
output "rag_bucket_name" {
  description = "Name of the S3 bucket for RAG documents and vectors"
  value       = aws_s3_bucket.rag_documents.bucket
}