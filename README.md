# Lightspeed Stack + vLLM Deployment on ROSA

This directory contains all the necessary manifests and scripts to deploy a complete Lightspeed Stack POC on Red Hat OpenShift Service on AWS (ROSA) with vLLM inference and RAG capabilities.

## Architecture

The deployment consists of three main components:

```
┌─────────────────────┐
│  Lightspeed Stack   │  ← User-facing API (Port 8080)
│   (REST API + UI)   │     - Query endpoint
└──────────┬──────────┘     - Streaming responses
           │                 - Web UI
           ↓
┌─────────────────────┐
│   Llama Stack       │  ← Middleware (Port 8321)
│  (Agent + RAG)      │     - Agent orchestration
└──────────┬──────────┘     - RAG runtime
           │                 - Tool calling
           ↓
┌─────────────────────┐
│      vLLM           │  ← Inference Engine (Port 8080)
│ (KServe/OpenShift   │     - LLM model serving
│      AI)            │     - GPU-accelerated
└─────────────────────┘     - Qwen 2.5 3B Instruct (32K context)
```

## Prerequisites

### Cluster Requirements

- **ROSA Cluster**: 4.12 or later
- **GPU Nodes**: At least 1 GPU node with NVIDIA GPU
  - Recommended: g5.2xlarge or similar (1 GPU, 8 vCPUs, 32 GiB RAM)
  - Model: Qwen/Qwen2.5-3B-Instruct (32K context window)
- **OpenShift AI**: RHOAI operator installed
- **NVIDIA GPU Operator**: Installed and configured
- **CLI Tools**:
  - `oc` (OpenShift CLI)
  - `kubectl`
  - `curl`
  - `jq`

### Required Tokens/Credentials

1. **HuggingFace Token**: For downloading the Llama model
   - Get from: https://huggingface.co/settings/tokens
   - Needs read access

2. **OpenShift Cluster**: Admin or namespace admin access

## Quick Start

If you have all prerequisites, use the automated deployment script:

```bash
cd deploy/rosa-poc/scripts
./deploy-all.sh
```

This script will:
1. Create namespace and secrets
2. Deploy vLLM
3. Deploy Llama Stack
4. Index RAG documents
5. Deploy Lightspeed Stack
6. Run tests

## Manual Deployment

For a step-by-step deployment, follow these instructions:

### Step 1: Verify Prerequisites

```bash
# Check you're logged into the cluster
oc whoami
oc cluster-info

# Verify GPU nodes are available
oc get nodes -l nvidia.com/gpu.present=true

# Check RHOAI operator is installed
oc get csv -n redhat-ods-operator | grep rhods
```

### Step 2: Create Namespace

```bash
cd 01-namespace
oc apply -f namespace.yaml
```

### Step 3: Create Secrets

```bash
cd ../02-secrets

# Set your HuggingFace token
export HF_TOKEN="your_huggingface_token_here"

# Create secrets
oc create secret generic hf-token-secret --from-literal=token="${HF_TOKEN}" -n lightspeed-poc
oc create secret generic vllm-api-key-secret --from-literal=key="poc-key-12345" -n lightspeed-poc
```

See `02-secrets/README.md` for more details.

### Step 4: Deploy vLLM

```bash
cd ../03-vllm

# Download and create chat template ConfigMap
./00-download-chat-template.sh

# Deploy vLLM ServingRuntime
oc apply -f 01-vllm-runtime-gpu.yaml

# Wait a moment for the runtime to be ready
sleep 5

# Deploy vLLM InferenceService
oc apply -f 02-vllm-inference-service-gpu.yaml

# Monitor the deployment
oc get pods -n lightspeed-poc -w
```

**Important**: Wait for vLLM pod to be ready and the model to be loaded. This can take 5-10 minutes.

Check status:
```bash
oc get inferenceservice -n lightspeed-poc
oc logs -f <vllm-pod-name> -n lightspeed-poc
```

See `03-vllm/README.md` for troubleshooting.

### Step 5: Deploy Llama Stack

```bash
cd ../04-llama-stack

# Get vLLM service URL and create secret
./00-get-vllm-url.sh

# Create Llama Stack ConfigMap
oc apply -f 01-llama-stack-configmap.yaml

# Deploy Llama Stack
oc apply -f 02-llama-stack-deployment.yaml

# Monitor deployment
oc get pods -n lightspeed-poc -w
```

Wait for the Llama Stack pod to be ready (usually 1-2 minutes).

See `04-llama-stack/README.md` for more details.

### Step 5a: Index RAG Documents

After Llama Stack is deployed and running, index the sample documents:

```bash
# Still in 04-llama-stack directory
./04-index-rag-docs.sh
```

This script will:
- Copy sample RHOAI documentation to the llama-stack pod
- Create chunks with proper document IDs
- Index chunks into the FAISS vector database
- Clean up temporary files

Expected output:
```
✅ RAG Indexing Complete!
   Vector Store: vs_xxxxx
   Total documents: 2
   Total chunks indexed: 4
```

**Important**: This step is required for RAG functionality. Without indexed documents, knowledge_search queries will return empty results.

### Step 6: Deploy Lightspeed Stack

```bash
cd ../05-lightspeed-stack

# Create ConfigMap
oc apply -f 01-lightspeed-stack-configmap.yaml

# Deploy Lightspeed Stack (Pod, Service, Route)
oc apply -f 02-lightspeed-stack-deployment.yaml

# Get the Route URL
LIGHTSPEED_URL=$(oc get route lightspeed-stack -n lightspeed-poc -o jsonpath='{.spec.host}')
echo "Lightspeed Stack URL: https://${LIGHTSPEED_URL}"
```

See `05-lightspeed-stack/README.md` for API details.

## Testing the Deployment

### Verify All Pods are Running

```bash
oc get pods -n lightspeed-poc
```

Expected output:
```
NAME                                        READY   STATUS    RESTARTS   AGE
vllm-llama-model-predictor-xxxxx            1/1     Running   0          10m
llama-stack-service                         1/1     Running   0          5m
lightspeed-stack-service                    1/1     Running   0          2m
```

### Access the Web UI

```bash
echo "Open https://$(oc get route lightspeed-stack -n lightspeed-poc -o jsonpath='{.spec.host}')"
```

Navigate to `/docs` for the Swagger UI.

### Run the Test Script

```bash
cd scripts
./test-deployment.sh
```

This script will:
1. Test all health endpoints
2. Send sample queries
3. Test RAG functionality
4. Verify streaming responses

### Interactive RAG Query Tool

Use the CLI tool to interactively query the RAG system:

```bash
cd scripts
./query-rag.sh
```

**Interactive mode** (prompt-based):
```bash
./query-rag.sh
> What are the key features of RHOAI?
```

**Single query mode**:
```bash
./query-rag.sh "What are the key features of RHOAI?"
```

**Disable RAG** (direct LLM query):
```bash
./query-rag.sh --no-tools "What is Kubernetes?"
```

The tool will:
- Automatically connect to your deployed instance
- Display formatted responses with token usage
- Show referenced documents when RAG is used
- Support multiple queries in interactive mode

### Manual API Tests

Get the Route URL:
```bash
LIGHTSPEED_URL=$(oc get route lightspeed-stack -n lightspeed-poc -o jsonpath='{.spec.host}')
```

Test basic query:
```bash
curl -X POST "https://${LIGHTSPEED_URL}/v1/query" \
  -H "Content-Type: application/json" \
  -d '{
    "query": "What is Kubernetes?",
    "system_prompt": "You are a helpful assistant."
  }' | jq .
```

Test RAG query (should use knowledge_search tool):
```bash
curl -X POST "https://${LIGHTSPEED_URL}/v1/query" \
  -H "Content-Type: application/json" \
  -d '{
    "query": "What are the key features of Red Hat OpenShift AI?",
    "no_tools": false
  }' | jq .
```

## Known Issues

### Model Information

**Current Model**: Qwen/Qwen2.5-3B-Instruct
- **Context Window**: 32,768 tokens (32K)
- **Parameters**: 3B
- **Memory**: ~6-7GB GPU memory
- **Strengths**: Excellent for chatbots, good instruction following, efficient

**Note**: This model was chosen for its large context window and efficiency. Previous model (Phi-3.5-mini-instruct) had only 2K context which caused failures with RAG queries.

### Model Output Format

**Issue**: Model responses may include raw JSON tool calls and special tokens like `<|eot_id|>` in the output.

**Root Cause**: The Phi-3.5-mini-instruct model doesn't fully adhere to the system prompt instructions to hide tool usage.

**Workaround**: The answer is still present in the response text. Users can parse or filter the relevant content.

## Troubleshooting

### General Debugging

View all resources:
```bash
oc get all -n lightspeed-poc
```

Check events:
```bash
oc get events -n lightspeed-poc --sort-by='.lastTimestamp' | tail -20
```

View logs for each component:
```bash
# vLLM
oc logs -f <vllm-pod-name> -n lightspeed-poc

# Llama Stack
oc logs -f llama-stack-service -n lightspeed-poc

# Lightspeed Stack
oc logs -f lightspeed-stack-service -n lightspeed-poc
```

### Common Issues

#### 1. vLLM Pod Not Starting

**GPU not available**:
```bash
# Check GPU nodes
oc get nodes -l nvidia.com/gpu.present=true

# Check GPU capacity
oc describe node <node-name> | grep -A 10 "Capacity"
```

**Model download failure**:
- Verify HuggingFace token is correct
- Check pod logs for download errors
- Ensure node has internet access

#### 2. Llama Stack Can't Connect to vLLM

**Check vLLM service**:
```bash
oc get svc -n lightspeed-poc | grep vllm
```

**Verify secret was created**:
```bash
oc get secret vllm-service-url -n lightspeed-poc
```

**Test connection**:
```bash
oc exec llama-stack-service -n lightspeed-poc -- \
  curl -s http://vllm-service-url/health
```

#### 3. RAG Not Working

**Check system prompt**: Verify the ConfigMap has the correct system prompt that instructs the model to use `knowledge_search`.

**Review Llama Stack logs**: Look for RAG tool calls:
```bash
oc logs llama-stack-service -n lightspeed-poc | grep -i "rag\|tool\|knowledge"
```

#### 4. Route Not Accessible

**Check route status**:
```bash
oc get route lightspeed-stack -n lightspeed-poc
oc describe route lightspeed-stack -n lightspeed-poc
```

**Verify TLS**:
```bash
curl -k -v https://$(oc get route lightspeed-stack -n lightspeed-poc -o jsonpath='{.spec.host}')/v1/info
```

## Monitoring

### Resource Usage

```bash
# Pod resource usage
oc adm top pods -n lightspeed-poc

# Node resource usage
oc adm top nodes
```

### Metrics

Access Prometheus metrics:
```bash
oc port-forward -n lightspeed-poc svc/lightspeed-stack-service 8080:8080
```

Then access `http://localhost:8080/metrics`

## Cleanup

To remove the entire POC deployment:

```bash
cd scripts
./cleanup.sh
```

Or manually:

```bash
oc delete namespace lightspeed-poc
```

## Production Considerations

This POC deployment is suitable for demonstration and testing. For production:

1. **Security**:
   - Enable authentication (K8s, OIDC, or API keys)
   - Use network policies
   - Implement RBAC
   - Secure secrets with Vault or similar

2. **High Availability**:
   - Deploy multiple replicas
   - Use persistent storage
   - Implement load balancing
   - Configure pod disruption budgets

3. **Data**:
   - Use persistent volumes for user data
   - Set up regular backups
   - Configure real RAG data sources
   - Use pgvector for production-scale vector store

4. **Monitoring**:
   - Set up Prometheus and Grafana
   - Configure alerting
   - Implement distributed tracing
   - Monitor GPU utilization

5. **Performance**:
   - Use larger models (Llama 3.1 8B or 70B)
   - Optimize batch sizes
   - Configure autoscaling
   - Monitor and optimize latency

## Next Steps

After successful POC deployment:

1. **Enhance RAG**:
   - Index full RHOAI documentation
   - Add more data sources
   - Test with various query types
   - Optimize retrieval parameters

2. **Test Scenarios**:
   - Load testing
   - Concurrent user simulation
   - Various query patterns
   - Tool calling accuracy

3. **Integration**:
   - Integrate with your applications
   - Set up CI/CD for updates
   - Configure monitoring and alerting
   - Plan for model updates

4. **Documentation**:
   - Document API usage
   - Create user guides
   - Record common issues and solutions
   - Share findings with stakeholders

## Support

For issues and questions:
- Lightspeed Stack: https://github.com/lightspeed-core/lightspeed-stack
- Red Hat OpenShift AI: Red Hat support portal
- vLLM: https://github.com/vllm-project/vllm

## License

This deployment configuration follows the Lightspeed Stack Apache 2.0 License.
