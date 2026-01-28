# Llama Stack Deployment

Llama Stack acts as middleware between lightspeed-stack and vLLM, providing:
- Agent orchestration
- RAG (Retrieval-Augmented Generation) capabilities
- Safety shields
- Tool runtime for function calling

## Prerequisites

- vLLM must be deployed and running (see `../03-vllm/`)
- Namespace and secrets must be created (see `../01-namespace/` and `../02-secrets/`)

## Deployment Steps

### 1. Get vLLM Service URL

After vLLM is deployed and running, get its service URL:

```bash
cd deploy/rosa-poc/04-llama-stack
./00-get-vllm-url.sh
```

This script will:
- Wait for the vLLM InferenceService to be ready
- Find the KServe-created predictor service
- Create a secret with the vLLM service URL

### 2. Create Llama Stack ConfigMap

```bash
oc apply -f 01-llama-stack-configmap.yaml
```

This creates a ConfigMap with the `run.yaml` configuration that:
- Configures vLLM as the remote inference provider
- Sets up the sentence-transformers embedding model for RAG
- Enables the RAG tool runtime
- Configures agents, safety shields, and vector stores

### 3. Deploy Llama Stack Pod and Service

```bash
oc apply -f 02-llama-stack-deployment.yaml
```

### 4. Verify Deployment

Wait for the pod to be ready:

```bash
oc get pods -n lightspeed-poc -w
```

Check pod logs:

```bash
oc logs -f llama-stack-service -n lightspeed-poc
```

You should see logs indicating:
- Llama Stack server starting on port 8321
- Loading configuration from run.yaml
- Initializing providers (vLLM, sentence-transformers, etc.)
- Server ready to accept requests

### 5. Test Llama Stack

Test the Llama Stack API:

```bash
# Get Llama Stack version
oc run test-llama-stack --rm -i --restart=Never \
  --image=curlimages/curl:latest -n lightspeed-poc -- \
  curl -s http://llama-stack-service.lightspeed-poc.svc.cluster.local:8321/v1/version

# List available models
oc run test-llama-stack --rm -i --restart=Never \
  --image=curlimages/curl:latest -n lightspeed-poc -- \
  curl -s http://llama-stack-service.lightspeed-poc.svc.cluster.local:8321/v1/models
```

Expected response should include `meta-llama/Llama-3.2-1B-Instruct` and the embedding model.

## Configuration Details

### run.yaml

The Llama Stack configuration includes:

1. **Inference Providers**:
   - `vllm`: Remote vLLM service for LLM inference
   - `sentence-transformers`: Local embedding model for RAG

2. **Vector Store**:
   - FAISS for vector storage
   - Sentence transformers for embeddings

3. **Agents**:
   - Meta-reference agent implementation
   - Agent state persistence in SQLite

4. **Tool Runtime**:
   - RAG runtime for knowledge search
   - Builtin RAG tool group enabled

5. **Safety**:
   - Llama Guard for content safety
   - Default shield configuration

### Environment Variables

The Llama Stack pod uses these environment variables:

- `VLLM_SERVICE_URL`: URL to the vLLM service (from secret)
- `VLLM_API_KEY`: API key for vLLM authentication (from secret)
- `KV_STORE_PATH`: Path for key-value store (vector DB metadata)
- `SQL_STORE_PATH`: Path for SQL store (agent state, responses)

## RAG Configuration

For this POC, RAG is configured with:
- **Embedding Model**: nomic-ai/nomic-embed-text-v1.5 (768 dimensions)
- **Vector Store**: FAISS (file-based)
- **Tool**: builtin::rag (knowledge_search)

To add vector data, see `README-RAG.md` in this directory.

## Troubleshooting

### Pod Not Starting

Check events:
```bash
oc describe pod llama-stack-service -n lightspeed-poc
```

Common issues:
- vLLM service URL secret not created
- ConfigMap not found
- Image pull issues

### Connection to vLLM Failed

Check vLLM service:
```bash
oc get svc -n lightspeed-poc | grep vllm
```

Test vLLM from within the cluster:
```bash
VLLM_URL=$(oc get secret vllm-service-url -n lightspeed-poc -o jsonpath='{.data.url}' | base64 -d)
oc run test-vllm-connection --rm -i --restart=Never \
  --image=curlimages/curl:latest -n lightspeed-poc -- \
  curl -s "${VLLM_URL}/health"
```

### Llama Stack API Errors

Check logs for detailed error messages:
```bash
oc logs llama-stack-service -n lightspeed-poc --tail=100
```

Common issues:
- vLLM not responding (model still loading)
- Invalid configuration in run.yaml
- Missing embedding model download

## Next Steps

Once Llama Stack is running successfully, you can:

1. Deploy Lightspeed Stack (see `../05-lightspeed-stack/`)
2. Test RAG queries through the complete stack
3. Monitor performance and logs
4. Configure additional vector databases with real data
