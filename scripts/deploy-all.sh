#!/bin/bash
# Automated deployment script for Lightspeed Stack POC on ROSA

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POC_DIR="$(dirname "$SCRIPT_DIR")"
NAMESPACE="lightspeed-poc"

echo "========================================="
echo "Lightspeed Stack + vLLM POC Deployment"
echo "========================================="
echo ""

# Function to print colored output
print_success() { echo -e "\033[0;32m✅ $1\033[0m"; }
print_error() { echo -e "\033[0;31m❌ $1\033[0m"; }
print_info() { echo -e "\033[0;34mℹ️  $1\033[0m"; }
print_warning() { echo -e "\033[0;33m⚠️  $1\033[0m"; }

# Function to wait for pod to be ready
wait_for_pod() {
    local pod_name=$1
    local timeout=${2:-300}

    print_info "Waiting for pod $pod_name to be ready (timeout: ${timeout}s)..."
    if oc wait --for=condition=Ready pod/$pod_name -n $NAMESPACE --timeout=${timeout}s 2>/dev/null; then
        print_success "Pod $pod_name is ready"
        return 0
    else
        print_error "Pod $pod_name failed to become ready"
        return 1
    fi
}

# Check prerequisites
echo "1. Checking prerequisites..."
echo "-----------------------------"

if ! command -v oc &> /dev/null; then
    print_error "oc CLI not found. Please install OpenShift CLI."
    exit 1
fi
print_success "oc CLI found"

if ! oc whoami &> /dev/null; then
    print_error "Not logged into OpenShift cluster. Please run 'oc login' first."
    exit 1
fi
print_success "Logged into OpenShift cluster: $(oc whoami --show-server)"

# Check for HuggingFace token
if [ -z "${HF_TOKEN:-}" ]; then
    print_warning "HF_TOKEN environment variable not set"
    read -p "Enter your HuggingFace token: " HF_TOKEN
    export HF_TOKEN
fi
print_success "HuggingFace token configured"

echo ""
echo "2. Verifying KServe is ready..."
echo "--------------------------------"

cd "$POC_DIR/00-prerequisites"
if ! ./wait-for-kserve.sh; then
    print_error "KServe is not ready. Please check the RHOAI installation."
    exit 1
fi

echo ""
echo "3. Creating namespace and secrets..."
echo "-------------------------------------"

cd "$POC_DIR/01-namespace"
oc apply -f namespace.yaml
print_success "Namespace created"

cd "$POC_DIR/02-secrets"
oc create secret generic hf-token-secret --from-literal=token="${HF_TOKEN}" -n $NAMESPACE --dry-run=client -o yaml | oc apply -f -
print_success "HuggingFace token secret created"

oc create secret generic vllm-api-key-secret --from-literal=key="poc-key-12345" -n $NAMESPACE --dry-run=client -o yaml | oc apply -f -
print_success "vLLM API key secret created"

# Check for Quay credentials
cd "$POC_DIR/02-secrets"
if [ -n "${QUAY_USERNAME:-}" ] && [ -n "${QUAY_PASSWORD:-}" ]; then
    print_info "Creating Quay.io pull secret..."
    ./create-quay-pull-secret.sh
    print_success "Quay.io pull secret created"
else
    print_warning "QUAY_USERNAME and QUAY_PASSWORD not set"
    print_info "If vLLM image pull fails, run: ./02-secrets/create-quay-pull-secret.sh"
fi

echo ""
echo "4. Deploying vLLM..."
echo "--------------------"

cd "$POC_DIR/03-vllm"

# Download chat template
print_info "Downloading chat template..."
./00-download-chat-template.sh
print_success "Chat template ConfigMap created"

# Deploy vLLM runtime
print_info "Deploying vLLM ServingRuntime..."
oc apply -f 01-vllm-runtime-gpu.yaml
sleep 5
print_success "vLLM ServingRuntime created"

# Deploy vLLM inference service
print_info "Deploying vLLM InferenceService..."
oc apply -f 02-vllm-inference-service-gpu.yaml
print_success "vLLM InferenceService created"

# Wait for vLLM pod
print_info "Waiting for vLLM pod to start (this may take 5-10 minutes for model download)..."
timeout=600
elapsed=0
while true; do
    vllm_pod=$(oc get pods -n $NAMESPACE -l component=predictor -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

    if [ -n "$vllm_pod" ]; then
        print_info "Found vLLM pod: $vllm_pod"
        if wait_for_pod "$vllm_pod" 600; then
            break
        else
            print_error "vLLM pod failed to become ready. Check logs: oc logs $vllm_pod -n $NAMESPACE"
            exit 1
        fi
    fi

    if [ $elapsed -ge $timeout ]; then
        print_error "Timeout waiting for vLLM pod to be created"
        exit 1
    fi

    echo "Waiting for vLLM pod to be created... ($elapsed/$timeout seconds)"
    sleep 10
    elapsed=$((elapsed + 10))
done

print_success "vLLM is running and model is loaded"

echo ""
echo "5. Deploying Llama Stack..."
echo "---------------------------"

cd "$POC_DIR/04-llama-stack"

# Get vLLM URL
print_info "Getting vLLM service URL..."
./00-get-vllm-url.sh
print_success "vLLM service URL secret created"

# Deploy Llama Stack
print_info "Deploying Llama Stack ConfigMap..."
oc apply -f 01-llama-stack-configmap.yaml
print_success "Llama Stack ConfigMap created"

print_info "Deploying Llama Stack Pod..."
oc apply -f 02-llama-stack-deployment.yaml
print_success "Llama Stack Pod created"

# Wait for Llama Stack
if wait_for_pod "llama-stack-service" 300; then
    print_success "Llama Stack is running"
else
    print_error "Llama Stack failed to start. Check logs: oc logs llama-stack-service -n $NAMESPACE"
    exit 1
fi

echo ""
echo "6. Deploying Lightspeed Stack..."
echo "---------------------------------"

cd "$POC_DIR/05-lightspeed-stack"

print_info "Deploying Lightspeed Stack ConfigMap..."
oc apply -f 01-lightspeed-stack-configmap.yaml
print_success "Lightspeed Stack ConfigMap created"

print_info "Deploying Lightspeed Stack (Pod, Service, Route)..."
oc apply -f 02-lightspeed-stack-deployment.yaml
print_success "Lightspeed Stack resources created"

# Wait for Lightspeed Stack
if wait_for_pod "lightspeed-stack-service" 180; then
    print_success "Lightspeed Stack is running"
else
    print_error "Lightspeed Stack failed to start. Check logs: oc logs lightspeed-stack-service -n $NAMESPACE"
    exit 1
fi

echo ""
echo "========================================="
echo "✅ DEPLOYMENT COMPLETE!"
echo "========================================="
echo ""

# Get the Route URL
LIGHTSPEED_URL=$(oc get route lightspeed-stack -n $NAMESPACE -o jsonpath='{.spec.host}' 2>/dev/null || echo "")

if [ -n "$LIGHTSPEED_URL" ]; then
    print_success "Lightspeed Stack is accessible at: https://${LIGHTSPEED_URL}"
    echo ""
    echo "Web UI: https://${LIGHTSPEED_URL}"
    echo "Swagger: https://${LIGHTSPEED_URL}/docs"
    echo "API Info: https://${LIGHTSPEED_URL}/v1/info"
else
    print_warning "Could not retrieve Route URL. Check: oc get route -n $NAMESPACE"
fi

echo ""
echo "All pods:"
oc get pods -n $NAMESPACE

echo ""
print_info "Run the test script to verify the deployment:"
echo "  cd $SCRIPT_DIR"
echo "  ./test-deployment.sh"
