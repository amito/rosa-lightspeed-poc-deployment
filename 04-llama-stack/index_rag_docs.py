#!/usr/bin/env python3
"""
Index sample RHOAI documentation into Llama Stack RAG vector database.

This script:
1. Creates or retrieves a vector store in Llama Stack
2. Reads sample documents from the mounted ConfigMap
3. Chunks documents for better retrieval
4. Generates embeddings and stores them in FAISS

Usage:
    python3 index_rag_docs.py
"""
import os
import sys
import json
import requests
from pathlib import Path

LLAMA_STACK_URL = "http://localhost:8321"
DOCS_DIR = "/tmp/sample-docs"


def chunk_text(text, chunk_size=500, overlap=50):
    """
    Split text into overlapping chunks for better retrieval.

    Args:
        text: The text to chunk
        chunk_size: Number of words per chunk
        overlap: Number of words to overlap between chunks

    Returns:
        List of text chunks
    """
    words = text.split()
    chunks = []

    for i in range(0, len(words), chunk_size - overlap):
        chunk = " ".join(words[i:i + chunk_size])
        if chunk:
            chunks.append(chunk)

    return chunks


def create_or_get_vector_store(name):
    """
    Create a new vector store or retrieve existing one by name.

    Args:
        name: The name of the vector store

    Returns:
        The vector store ID
    """
    print("Checking for existing vector store...")

    # List existing vector stores
    response = requests.get(f"{LLAMA_STACK_URL}/v1/vector_stores", timeout=10)
    if response.status_code == 200:
        stores = response.json().get("data", [])
        for store in stores:
            if store.get("name") == name:
                store_id = store["id"]
                print(f"✅ Found existing vector store: {store_id}")
                return store_id

    # Create new vector store
    print(f"Creating new vector store: {name}")
    response = requests.post(
        f"{LLAMA_STACK_URL}/v1/vector_stores",
        json={"name": name, "file_ids": []},
        timeout=10
    )

    if response.status_code == 200:
        store_id = response.json()["id"]
        print(f"✅ Created vector store: {store_id}")
        return store_id
    else:
        print(f"❌ Error creating vector store: {response.status_code}")
        print(f"   Response: {response.text}")
        sys.exit(1)


def index_document(file_path, vector_db_id):
    """
    Index a single document file into the vector database.

    Args:
        file_path: Path to the document file
        vector_db_id: ID of the vector database to insert into

    Returns:
        Number of successfully indexed chunks
    """
    print(f"📄 Processing: {file_path.name}")

    with open(file_path, 'r') as f:
        content = f.read()

    # Chunk the document
    chunks = chunk_text(content)
    print(f"   Created {len(chunks)} chunks")

    # Insert each chunk into the vector database
    success_count = 0
    for idx, chunk in enumerate(chunks):
        try:
            # Prepare the chunk for insertion
            chunk_data = {
                "content": chunk,
                "metadata": {
                    "document_id": file_path.name,
                    "source": file_path.name,
                    "chunk_index": idx,
                    "total_chunks": len(chunks)
                }
            }

            # Insert into vector database via Llama Stack API
            response = requests.post(
                f"{LLAMA_STACK_URL}/v1/vector-io/insert",
                json={
                    "vector_db_id": vector_db_id,
                    "chunks": [chunk_data]
                },
                timeout=30
            )

            if response.status_code == 200:
                success_count += 1
            else:
                print(f"   ⚠️  Warning: Failed to insert chunk {idx}: {response.status_code}")
                print(f"   Response: {response.text}")

        except Exception as e:
            print(f"   ❌ Error inserting chunk {idx}: {e}")

    print(f"   ✅ Successfully indexed {success_count}/{len(chunks)} chunks")
    return success_count


def main():
    """Main indexing function."""
    print("=" * 50)
    print("RAG Document Indexing")
    print("=" * 50)
    print(f"Documents: {DOCS_DIR}")
    print("")

    # Create or get vector store
    vector_db_id = create_or_get_vector_store("rhoai-docs")
    print(f"Using Vector Store ID: {vector_db_id}")
    print("")

    # Check if documents directory exists
    docs_path = Path(DOCS_DIR)
    if not docs_path.exists():
        print(f"❌ Error: Documents directory not found: {DOCS_DIR}")
        sys.exit(1)

    # Find all .txt files
    doc_files = list(docs_path.glob("*.txt"))
    if not doc_files:
        print(f"❌ Error: No .txt files found in {DOCS_DIR}")
        sys.exit(1)

    print(f"Found {len(doc_files)} document(s) to index")
    print("")

    # Index each document
    total_chunks = 0
    for doc_file in sorted(doc_files):
        chunks = index_document(doc_file, vector_db_id)
        total_chunks += chunks

    print("")
    print("=" * 50)
    print(f"✅ Indexing Complete!")
    print(f"   Vector Store: {vector_db_id}")
    print(f"   Total documents: {len(doc_files)}")
    print(f"   Total chunks indexed: {total_chunks}")
    print("=" * 50)


if __name__ == "__main__":
    main()
