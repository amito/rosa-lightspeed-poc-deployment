# Quick Start Guide

Get your Lightspeed Stack + vLLM POC running on ROSA in minutes!

## Prerequisites Checklist

**IMPORTANT**: Run the prerequisite check first:

```bash
cd deploy/rosa-poc/00-prerequisites
./check-prerequisites.sh
```

This checks:
- [ ] ROSA cluster with GPU nodes
- [ ] Logged into the cluster: `oc login`
- [ ] **RHOAI operator installed** (REQUIRED for KServe CRDs)
- [ ] **DataScienceCluster created with KServe enabled** (REQUIRED)
- [ ] NVIDIA GPU operator installed (for GPU deployment)
- [ ] HuggingFace account and token (https://huggingface.co/settings/tokens)
- [ ] **Red Hat Quay.io credentials** (https://access.redhat.com/terms-based-registry/)

**If checks fail**, see `00-prerequisites/setup-rhoai.md` for setup instructions.

## One-Command Deploy

```bash
export HF_TOKEN="your_huggingface_token_here"
export QUAY_USERNAME="your_quay_username"
export QUAY_PASSWORD="your_quay_password_or_token"
cd deploy/rosa-poc/scripts
./deploy-all.sh
```

**Note**: Get Quay credentials from https://access.redhat.com/terms-based-registry/

This script will:
1. ✅ Create namespace and secrets
2. ✅ Deploy vLLM with Llama 3.2 1B model
3. ✅ Deploy Llama Stack middleware
4. ✅ Deploy Lightspeed Stack API
5. ✅ Expose external Route

**Expected time**: 15-20 minutes (mostly model download)

## Manual Deployment

If you prefer step-by-step control:

### 1. Setup (2 minutes)

```bash
# Create namespace
oc apply -f 01-namespace/namespace.yaml

# Create secrets
export HF_TOKEN="your_token_here"
export QUAY_USERNAME="your_quay_username"
export QUAY_PASSWORD="your_quay_password"

oc create secret generic hf-token-secret --from-literal=token="${HF_TOKEN}" -n lightspeed-poc
oc create secret generic vllm-api-key-secret --from-literal=key="poc-key-12345" -n lightspeed-poc

# Create Quay pull secret
cd 02-secrets
./create-quay-pull-secret.sh
cd ..
```

### 2. Deploy vLLM (10-15 minutes)

```bash
cd 03-vllm
./00-download-chat-template.sh
oc apply -f 01-vllm-runtime-gpu.yaml
sleep 5
oc apply -f 02-vllm-inference-service-gpu.yaml

# Monitor deployment
oc get pods -n lightspeed-poc -w
```

### 3. Deploy Llama Stack (2-3 minutes)

```bash
cd ../04-llama-stack
./00-get-vllm-url.sh
oc apply -f 01-llama-stack-configmap.yaml
oc apply -f 02-llama-stack-deployment.yaml

# Wait for ready
oc wait --for=condition=Ready pod/llama-stack-service -n lightspeed-poc --timeout=300s
```

### 4. Deploy Lightspeed Stack (1-2 minutes)

```bash
cd ../05-lightspeed-stack
oc apply -f 01-lightspeed-stack-configmap.yaml
oc apply -f 02-lightspeed-stack-deployment.yaml

# Get the URL
echo "https://$(oc get route lightspeed-stack -n lightspeed-poc -o jsonpath='{.spec.host}')"
```

## Testing

```bash
cd scripts
./test-deployment.sh
```

Or test manually:

```bash
LIGHTSPEED_URL=$(oc get route lightspeed-stack -n lightspeed-poc -o jsonpath='{.spec.host}')

# Test basic query
curl -X POST "https://${LIGHTSPEED_URL}/v1/query" \
  -H "Content-Type: application/json" \
  -d '{"query": "What is Kubernetes?"}' | jq .

# Test RAG
curl -X POST "https://${LIGHTSPEED_URL}/v1/query" \
  -H "Content-Type: application/json" \
  -d '{"query": "What are the key features of Red Hat OpenShift AI?"}' | jq .
```

## Access Points

- **Web UI**: `https://<route-url>`
- **Swagger**: `https://<route-url>/docs`
- **API Info**: `https://<route-url>/v1/info`
- **Models**: `https://<route-url>/v1/models`

## Cleanup

```bash
cd scripts
./cleanup.sh
```

Or simply:

```bash
oc delete namespace lightspeed-poc
```

## Troubleshooting

**vLLM pod stuck in pending?**
```bash
oc get nodes -l nvidia.com/gpu.present=true
oc describe pod <vllm-pod> -n lightspeed-poc
```

**Model download slow?**
- Normal for first deployment (5-10 minutes)
- Check logs: `oc logs -f <vllm-pod> -n lightspeed-poc`

**Llama Stack can't connect to vLLM?**
```bash
oc get secret vllm-service-url -n lightspeed-poc
oc logs llama-stack-service -n lightspeed-poc
```

**RAG not working?**
- Check system prompt in ConfigMap includes knowledge_search instruction
- Verify `no_tools: false` in your query
- Review Llama Stack logs for tool calls

## Next Steps

1. ✅ Access the Web UI
2. ✅ Run the test script
3. ✅ Try various RAG queries
4. ✅ Explore Swagger UI
5. ✅ Check the full README.md for production considerations

## Support

- Main README: `./README.md`
- Component READMEs: See each subdirectory
- Issues: https://github.com/lightspeed-core/lightspeed-stack/issues
