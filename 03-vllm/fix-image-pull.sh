#!/bin/bash
# Script to fix ImagePullBackOff by recreating the InferenceService with pull secret

set -euo pipefail

NAMESPACE="lightspeed-poc"

echo "========================================="
echo "Fix vLLM Image Pull Issue"
echo "========================================="
echo ""

# Function to print colored output
print_success() { echo -e "\033[0;32m✅ $1\033[0m"; }
print_error() { echo -e "\033[0;31m❌ $1\033[0m"; }
print_info() { echo -e "\033[0;34mℹ️  $1\033[0m"; }

# Check if pull secret exists
if ! oc get secret rh-quay-pull-secret -n $NAMESPACE &> /dev/null; then
    print_error "Pull secret 'rh-quay-pull-secret' not found"
    echo ""
    print_info "Create it first:"
    echo "  cd ../02-secrets"
    echo "  ./create-quay-pull-secret.sh"
    exit 1
fi

print_success "Pull secret exists"

# Check if it's linked to service account
print_info "Verifying secret is linked to service account..."
if oc get sa default -n $NAMESPACE -o jsonpath='{.imagePullSecrets[*].name}' | grep -q rh-quay-pull-secret; then
    print_success "Secret is linked to default service account"
else
    print_info "Linking secret to service account..."
    oc secrets link default rh-quay-pull-secret --for=pull -n $NAMESPACE
    print_success "Secret linked"
fi

echo ""
print_info "Deleting InferenceService to force recreation..."

# Delete the InferenceService
if oc delete inferenceservice vllm-llama-model -n $NAMESPACE; then
    print_success "InferenceService deleted"
else
    print_error "Failed to delete InferenceService (it may not exist)"
fi

# Wait for resources to be cleaned up
print_info "Waiting for resources to be cleaned up..."
sleep 10

echo ""
print_info "Recreating InferenceService..."

# Recreate the InferenceService
if oc apply -f 02-vllm-inference-service-gpu.yaml; then
    print_success "InferenceService created"
else
    print_error "Failed to create InferenceService"
    exit 1
fi

echo ""
print_info "Waiting for new pod to start..."
sleep 5

# Get the new pod name
timeout=60
elapsed=0
while true; do
    pod_name=$(oc get pods -n $NAMESPACE -l component=predictor -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

    if [ -n "$pod_name" ]; then
        print_success "New pod created: $pod_name"
        break
    fi

    if [ $elapsed -ge $timeout ]; then
        print_error "Timeout waiting for pod to be created"
        exit 1
    fi

    echo "Waiting for pod... ($elapsed/$timeout seconds)"
    sleep 5
    elapsed=$((elapsed + 5))
done

echo ""
print_info "Monitoring pod status..."
echo ""

# Show pod events
oc get events -n $NAMESPACE --field-selector involvedObject.name=$pod_name --sort-by='.lastTimestamp' | tail -10

echo ""
print_info "Checking image pull status..."

# Wait a moment for image pull to start
sleep 10

# Check pod status
pod_status=$(oc get pod $pod_name -n $NAMESPACE -o jsonpath='{.status.phase}')
image_pull_status=$(oc get pod $pod_name -n $NAMESPACE -o jsonpath='{.status.containerStatuses[0].state}' 2>/dev/null || echo "")

if echo "$image_pull_status" | grep -q "ImagePullBackOff\|ErrImagePull"; then
    print_error "Still getting ImagePullBackOff"
    echo ""
    print_info "Checking pod details..."
    oc describe pod $pod_name -n $NAMESPACE | grep -A 10 "Events:"
    echo ""
    print_error "The pull secret may not be working. Verify your Quay credentials."
    exit 1
elif echo "$image_pull_status" | grep -q "running\|waiting"; then
    print_success "Image pull in progress or container starting"
else
    print_success "Pod status: $pod_status"
fi

echo ""
print_info "Follow the logs with:"
echo "  oc logs -f $pod_name -n $NAMESPACE"
echo ""
print_info "Watch pod status with:"
echo "  oc get pods -n $NAMESPACE -w"
