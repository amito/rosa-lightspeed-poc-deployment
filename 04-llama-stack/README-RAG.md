# RAG Data Source Setup

This directory contains sample documentation and instructions for setting up a RAG (Retrieval-Augmented Generation) data source for the POC.

## Option 1: Quick Mock Data (Recommended for POC)

We've provided sample RHOAI documentation in the `sample-docs/` directory. For a quick POC, you can use the `byok_rag` (Bring Your Own Knowledge RAG) configuration which allows you to provide pre-built FAISS vector databases.

### Quick Setup - Use Pre-built ConfigMap

1. The sample docs are already available in `sample-docs/`:
   - `rhoai-overview.txt` - Overview of Red Hat OpenShift AI
   - `rhoai-inference.txt` - Detailed inference guide

2. For the POC, we'll configure Llama Stack to use the built-in RAG runtime with these documents loaded into the vector store during deployment.

## Option 2: Build RAG Database Using rag-content Tool (Production)

For a production-ready setup with actual RHOAI documentation:

### Prerequisites

```bash
# Clone the rag-content repository
git clone https://github.com/lightspeed-core/rag-content.git
cd rag-content
```

### Steps

1. **Scrape RHOAI Documentation**

```bash
# Configure the scraper for RHOAI docs
# Edit the configuration to point to RHOAI documentation sources
```

2. **Generate Vector Database**

```bash
# Run the indexing tool
python -m rag_content.index \
  --source docs/rhoai \
  --output-dir ./vector_dbs/rhoai \
  --embedding-model sentence-transformers/all-mpnet-base-v2 \
  --vector-db-type faiss \
  --vector-db-id rhoai-docs
```

3. **Download Embedding Model**

```bash
# Download the embedding model locally
python -m rag_content.download_model \
  --model sentence-transformers/all-mpnet-base-v2 \
  --output-dir ./embedding_models
```

4. **Create PersistentVolume for RAG Data**

```bash
# Create a PVC to store the vector database
oc create -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: rag-data
  namespace: lightspeed-poc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
EOF
```

5. **Copy Data to PVC**

```bash
# Create a temporary pod to upload data
oc run rag-upload --rm -i --image=registry.access.redhat.com/ubi9/ubi-minimal:latest \
  --overrides='
  {
    "spec": {
      "containers": [{
        "name": "rag-upload",
        "image": "registry.access.redhat.com/ubi9/ubi-minimal:latest",
        "command": ["sleep", "3600"],
        "volumeMounts": [{
          "name": "rag-data",
          "mountPath": "/data"
        }]
      }],
      "volumes": [{
        "name": "rag-data",
        "persistentVolumeClaim": {
          "claimName": "rag-data"
        }
      }]
    }
  }' -n lightspeed-poc

# Copy the vector DB and embedding model
oc cp ./vector_dbs/rhoai rag-upload:/data/vector_db -n lightspeed-poc
oc cp ./embedding_models/all-mpnet-base-v2 rag-upload:/data/embedding_model -n lightspeed-poc

# Delete the upload pod
oc delete pod rag-upload -n lightspeed-poc
```

## POC Configuration

For this POC, we'll use a simplified approach:

The Llama Stack configuration (`run.yaml`) will be set up to use sample documentation that can be easily replaced with real data later. The configuration will include:

1. **Embedding Model**: sentence-transformers (inline provider)
2. **Vector Store**: FAISS (file-based)
3. **RAG Runtime**: Built-in Llama Stack RAG runtime
4. **Sample Data**: RHOAI documentation excerpts

## Testing RAG

Once deployed, you can test RAG queries like:

```bash
# Query about RHOAI features
curl -X POST http://lightspeed-service/v1/query \
  -H "Content-Type: application/json" \
  -d '{
    "query": "What are the key features of Red Hat OpenShift AI?",
    "system_prompt": "You are a helpful assistant. Use the knowledge_search tool to find information before answering."
  }'

# Query about inference
curl -X POST http://lightspeed-service/v1/query \
  -H "Content-Type: application/json" \
  -d '{
    "query": "How do I deploy a model for inference in RHOAI?",
    "system_prompt": "You are a helpful assistant. Use the knowledge_search tool to find accurate information from the documentation before answering."
  }'
```

## Next Steps

After POC validation, you can:

1. Replace sample docs with full RHOAI documentation
2. Add more documentation sources
3. Update the vector database with fresh content
4. Configure pgvector for production scalability
5. Set up automated documentation updates
