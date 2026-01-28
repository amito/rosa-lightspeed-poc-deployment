# vLLM Deployment

This directory contains manifests for deploying vLLM on ROSA with GPU support.

## Prerequisites

1. **GPU Nodes**: Ensure your ROSA cluster has GPU-enabled nodes
2. **NVIDIA Operator**: Install the NVIDIA GPU operator if not already installed
3. **OpenShift AI**: RHOAI operator should be installed and configured

## Deployment Steps

### 1. Download and Create Chat Template ConfigMap

```bash
cd deploy/rosa-poc/03-vllm
./00-download-chat-template.sh
```

This downloads the Llama 3.2 chat template from vLLM repository and creates a ConfigMap.

### 2. Deploy vLLM ServingRuntime

```bash
oc apply -f 01-vllm-runtime-gpu.yaml
```

Wait for the ServingRuntime to be created:

```bash
oc get servingruntime -n lightspeed-poc
```

### 3. Deploy vLLM InferenceService

```bash
oc apply -f 02-vllm-inference-service-gpu.yaml
```

### 4. Monitor Deployment

Watch the pods:

```bash
oc get pods -n lightspeed-poc -w
```

Check the InferenceService status:

```bash
oc get inferenceservice -n lightspeed-poc
```

### 5. Get the vLLM Service URL

```bash
oc get svc -n lightspeed-poc | grep vllm
```

The service name will be similar to `vllm-llama-model-predictor` or check the InferenceService status for the URL.

## Testing vLLM

Once the pod is running and the model is loaded (this can take 5-10 minutes), you can test the vLLM endpoint:

```bash
# Get the service URL
VLLM_SERVICE=$(oc get svc -n lightspeed-poc -o jsonpath='{.items[?(@.metadata.labels.component=="predictor")].metadata.name}' | head -n1)
VLLM_URL="http://${VLLM_SERVICE}.lightspeed-poc.svc.cluster.local:8080"

# Get the API key
VLLM_API_KEY=$(oc get secret vllm-api-key-secret -n lightspeed-poc -o jsonpath='{.data.key}' | base64 -d)

# Test with a curl pod
oc run test-vllm --rm -i --restart=Never --image=curlimages/curl:latest -n lightspeed-poc -- \
  curl -s -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${VLLM_API_KEY}" \
  -d '{"model": "meta-llama/Llama-3.2-1B-Instruct", "prompt": "What is Kubernetes?", "max_tokens": 100}' \
  "${VLLM_URL}/v1/completions"
```

## Troubleshooting

### Check Pod Logs

```bash
POD_NAME=$(oc get pods -n lightspeed-poc -l component=predictor -o jsonpath='{.items[0].metadata.name}')
oc logs -f ${POD_NAME} -n lightspeed-poc
```

### Check Events

```bash
oc get events -n lightspeed-poc --sort-by='.lastTimestamp' | tail -20
```

### GPU Issues

If the pod is not starting due to GPU issues:

```bash
# Check GPU nodes
oc get nodes -l nvidia.com/gpu.present=true

# Check GPU capacity
oc describe node <gpu-node-name> | grep -A 10 "Capacity"
```

## CPU-only Deployment (Not Recommended for POC)

If you don't have GPU nodes, you can use a CPU-only deployment, but performance will be significantly slower. Contact the maintainers for CPU-specific manifests if needed.

## Configuration

The vLLM deployment is configured to:
- Use `meta-llama/Llama-3.2-1B-Instruct` model
- Enable tool calling with JSON mode
- Use 90% of GPU memory
- Max model length: 2048 tokens
- Download models to `/tmp/models-cache`

You can modify these settings in `01-vllm-runtime-gpu.yaml`.
