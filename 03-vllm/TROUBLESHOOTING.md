# vLLM Deployment Troubleshooting

## Image Pull Issues

### Problem: ImagePullBackOff with quay.io/modh/vllm image

**Error:**
```
Failed to pull image "quay.io/modh/vllm:v0.6.5-2024b-6":
rpc error: code = Unknown desc = Error reading manifest
```

**Cause**: The `quay.io/modh/vllm` image is from Red Hat's internal registry and requires authentication.

**Solutions:**

#### Option 1: Use Public vLLM Image (Recommended for POC)

Replace the current ServingRuntime with the public image version:

```bash
# Delete the existing ServingRuntime
oc delete servingruntime vllm-gpu -n lightspeed-poc

# Apply the public image version
oc apply -f 01-vllm-runtime-gpu-public.yaml
```

The public image uses `docker.io/vllm/vllm-openai:v0.6.3.post1` which is freely available.

#### Option 2: Authenticate to Red Hat Registry (If you have access)

If you have access to Red Hat's registry, create a pull secret:

```bash
# Get your Red Hat registry credentials
# From: https://access.redhat.com/terms-based-registry/

oc create secret docker-registry rh-registry-pull-secret \
  --docker-server=quay.io \
  --docker-username='<your-username>' \
  --docker-password='<your-password>' \
  -n lightspeed-poc

# Link the secret to the default service account
oc secrets link default rh-registry-pull-secret --for=pull -n lightspeed-poc
```

Then use the original manifest:
```bash
oc apply -f 01-vllm-runtime-gpu.yaml
```

#### Option 3: Use Latest vLLM Image

For the absolute latest features:

```bash
# Edit the ServingRuntime
oc edit servingruntime vllm-gpu -n lightspeed-poc

# Change the image to:
image: docker.io/vllm/vllm-openai:latest
```

### Check Image Pull Status

```bash
# Get the pod name
POD=$(oc get pods -n lightspeed-poc -l component=predictor -o jsonpath='{.items[0].metadata.name}')

# Check events
oc describe pod $POD -n lightspeed-poc | grep -A 10 Events

# Check image pull progress
oc get events -n lightspeed-poc --field-selector involvedObject.name=$POD
```

## Model Download Issues

### Problem: Model download is slow or failing

**Check download progress:**

```bash
# Watch the logs
oc logs -f $POD -n lightspeed-poc

# Look for lines like:
# Downloading meta-llama/Llama-3.2-1B-Instruct
# Downloading (…): 100%|██████████| 1.23G/1.23G
```

**Solutions:**

1. **Wait patiently**: First download can take 5-15 minutes depending on network speed

2. **Check HuggingFace token**:
   ```bash
   # Verify token is set correctly
   oc get secret hf-token-secret -n lightspeed-poc -o jsonpath='{.data.token}' | base64 -d
   ```

3. **Check network connectivity**:
   ```bash
   # Test from within the pod (if it starts)
   oc exec $POD -n lightspeed-poc -- curl -I https://huggingface.co
   ```

4. **Use a smaller model for testing**:
   Edit the ServingRuntime and change:
   ```yaml
   - --model
   - meta-llama/Llama-3.2-1B-Instruct  # Only 2.5GB
   ```

## GPU Issues

### Problem: Pod pending with "Insufficient nvidia.com/gpu"

**Check GPU availability:**

```bash
# List GPU nodes
oc get nodes -l nvidia.com/gpu.present=true

# Check GPU capacity on each node
oc describe nodes -l nvidia.com/gpu.present=true | grep -A 5 "Capacity"

# Check GPU allocation
oc describe nodes -l nvidia.com/gpu.present=true | grep -A 5 "Allocated"
```

**Solutions:**

1. **Ensure GPU nodes exist**: See main README for adding GPU nodes to ROSA

2. **Check if GPUs are being used by other pods**:
   ```bash
   oc get pods -A -o json | jq '.items[] | select(.spec.containers[].resources.limits."nvidia.com/gpu" != null) | {name: .metadata.name, namespace: .metadata.namespace, gpu: .spec.containers[].resources.limits."nvidia.com/gpu"}'
   ```

3. **Reduce GPU memory requirement** (temporary):
   Edit the ServingRuntime:
   ```yaml
   resources:
     limits:
       nvidia.com/gpu: 1
       memory: 16Gi  # Reduced from 20Gi
   ```

### Problem: GPU detected but not being used

**Check NVIDIA device plugin:**

```bash
# Check if device plugin is running
oc get pods -n nvidia-gpu-operator -l app=nvidia-device-plugin-daemonset

# Check logs
oc logs -n nvidia-gpu-operator -l app=nvidia-device-plugin-daemonset
```

**Solution**: Ensure NVIDIA GPU Operator is properly installed (see `../00-prerequisites/setup-rhoai.md`)

## Container Crashes

### Problem: Pod in CrashLoopBackOff

**Check logs:**

```bash
# Current logs
oc logs $POD -n lightspeed-poc

# Previous crash logs
oc logs $POD -n lightspeed-poc --previous
```

**Common issues and solutions:**

1. **Out of Memory**:
   ```
   Error: CUDA out of memory
   ```
   Solution: Reduce `--gpu-memory-utilization` or use smaller model

2. **Chat template not found**:
   ```
   Error: Could not find chat template
   ```
   Solution: Ensure ConfigMap was created:
   ```bash
   oc get configmap vllm-chat-template -n lightspeed-poc
   ```

3. **Model architecture mismatch**:
   ```
   Error: Model architecture not supported
   ```
   Solution: Ensure using a supported Llama model variant

## InferenceService Issues

### Problem: InferenceService status shows "Failed"

**Check InferenceService status:**

```bash
oc get inferenceservice vllm-llama-model -n lightspeed-poc -o yaml
```

Look at the `status.conditions` section for error messages.

**Check KNative Service:**

```bash
# KServe creates a KNative Service
oc get ksvc -n lightspeed-poc

# Check its status
oc describe ksvc vllm-llama-model-predictor -n lightspeed-poc
```

### Problem: Service not getting external URL

**Check Knative networking:**

```bash
# Check if Knative Serving is healthy
oc get pods -n knative-serving

# Check ingress gateway
oc get svc -n istio-system
```

## Performance Issues

### Problem: Inference is very slow

**Check resource allocation:**

```bash
# Check actual resource usage
oc adm top pod $POD -n lightspeed-poc

# Compare with limits
oc get pod $POD -n lightspeed-poc -o jsonpath='{.spec.containers[0].resources}'
```

**Tuning options:**

1. **Increase GPU memory utilization**:
   ```yaml
   args:
     - --gpu-memory-utilization
     - "0.95"  # Increased from 0.9
   ```

2. **Adjust max model length**:
   ```yaml
   args:
     - --max-model-len
     - "4096"  # Increased from 2048
   ```

3. **Enable tensor parallelism** (for multi-GPU):
   ```yaml
   args:
     - --tensor-parallel-size
     - "2"  # For 2 GPUs
   ```

## Quick Fixes

### Restart the vLLM pod

```bash
# Delete the pod (it will be recreated)
oc delete pod $POD -n lightspeed-poc

# Or delete and recreate the InferenceService
oc delete inferenceservice vllm-llama-model -n lightspeed-poc
oc apply -f 02-vllm-inference-service-gpu.yaml
```

### Reset everything

```bash
# Delete all vLLM resources
oc delete inferenceservice vllm-llama-model -n lightspeed-poc
oc delete servingruntime vllm-gpu -n lightspeed-poc

# Wait a moment
sleep 10

# Redeploy
oc apply -f 01-vllm-runtime-gpu-public.yaml
oc apply -f 02-vllm-inference-service-gpu.yaml
```

## Getting More Information

### Complete diagnostic dump

```bash
# Create a diagnostic report
mkdir -p /tmp/vllm-diagnostics

# Get all resources
oc get all -n lightspeed-poc -o yaml > /tmp/vllm-diagnostics/all-resources.yaml

# Get events
oc get events -n lightspeed-poc --sort-by='.lastTimestamp' > /tmp/vllm-diagnostics/events.txt

# Get pod descriptions
oc describe pods -n lightspeed-poc > /tmp/vllm-diagnostics/pod-descriptions.txt

# Get logs
oc logs -n lightspeed-poc --all-containers=true --max-log-requests=10 > /tmp/vllm-diagnostics/logs.txt

echo "Diagnostic information saved to /tmp/vllm-diagnostics/"
```

## Additional Resources

- [vLLM Documentation](https://docs.vllm.ai/)
- [KServe Documentation](https://kserve.github.io/website/)
- [RHOAI Model Serving Guide](https://access.redhat.com/documentation/en-us/red_hat_openshift_ai_self-managed)
