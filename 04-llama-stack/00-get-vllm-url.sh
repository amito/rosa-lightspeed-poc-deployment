#!/bin/bash
# This script gets the vLLM service URL and creates a secret for Llama Stack to use

set -euo pipefail

NAMESPACE="lightspeed-poc"

echo "Waiting for vLLM InferenceService to be ready..."

# Wait for the InferenceService to be ready
timeout=300
elapsed=0
while true; do
    status=$(oc get inferenceservice vllm-llama-model -n ${NAMESPACE} -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "False")

    if [ "$status" == "True" ]; then
        echo "✅ InferenceService is ready"
        break
    fi

    if [ $elapsed -ge $timeout ]; then
        echo "❌ Timeout waiting for InferenceService to be ready"
        echo "Current status:"
        oc get inferenceservice vllm-llama-model -n ${NAMESPACE}
        exit 1
    fi

    echo "Waiting... ($elapsed/$timeout seconds)"
    sleep 10
    elapsed=$((elapsed + 10))
done

# Get the predictor service name (KServe creates this)
echo "Finding vLLM service..."
VLLM_SERVICE=$(oc get svc -n ${NAMESPACE} -l serving.kserve.io/inferenceservice=vllm-llama-model,component=predictor -o jsonpath='{.items[0].metadata.name}')

if [ -z "$VLLM_SERVICE" ]; then
    echo "❌ Could not find vLLM service"
    echo "Available services:"
    oc get svc -n ${NAMESPACE}
    exit 1
fi

echo "Found vLLM service: $VLLM_SERVICE"

# Construct the full URL
VLLM_URL="http://${VLLM_SERVICE}.${NAMESPACE}.svc.cluster.local:8080"
echo "vLLM service URL: $VLLM_URL"

# Create or update the secret
echo "Creating secret with vLLM service URL..."
oc create secret generic vllm-service-url \
    --from-literal=url="${VLLM_URL}" \
    -n ${NAMESPACE} \
    --dry-run=client -o yaml | oc apply -f -

echo "✅ Secret created/updated: vllm-service-url"
echo ""
echo "You can now deploy Llama Stack:"
echo "  oc apply -f 02-llama-stack-deployment.yaml"
