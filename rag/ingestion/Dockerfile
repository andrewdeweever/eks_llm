FROM python:3.10-slim

WORKDIR /app

# Install system dependencies for PDF support if needed
RUN apt-get update && apt-get install -y \
    gcc \
    g++ \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the script
COPY ingest.py .

# Run the ingestion
CMD ["python", "ingest.py"]