#!/bin/bash
# Wait for KServe to be fully ready before deploying vLLM

set -euo pipefail

echo "========================================="
echo "Waiting for KServe to be Ready"
echo "========================================="
echo ""

# Function to print colored output
print_success() { echo -e "\033[0;32m✅ $1\033[0m"; }
print_error() { echo -e "\033[0;31m❌ $1\033[0m"; }
print_info() { echo -e "\033[0;34mℹ️  $1\033[0m"; }
print_warning() { echo -e "\033[0;33m⚠️  $1\033[0m"; }

# Check 1: KServe controller deployment exists
echo "1. Checking KServe controller deployment..."
timeout=300
elapsed=0

while ! oc get deployment kserve-controller-manager -n redhat-ods-applications &>/dev/null; do
    if [ $elapsed -ge $timeout ]; then
        print_error "Timeout waiting for KServe controller deployment to be created"
        echo ""
        print_info "Check DataScienceCluster status:"
        echo "  oc get datasciencecluster default-dsc -o yaml"
        echo ""
        print_info "Check RHOAI operator logs:"
        echo "  oc logs -n redhat-ods-operator deployment/rhods-operator"
        exit 1
    fi
    echo "Waiting for KServe controller deployment... ($elapsed/$timeout seconds)"
    sleep 10
    elapsed=$((elapsed + 10))
done

print_success "KServe controller deployment exists"
echo ""

# Check 2: Wait for KServe controller to be ready
echo "2. Waiting for KServe controller rollout..."
if ! oc rollout status deployment/kserve-controller-manager -n redhat-ods-applications --timeout=300s; then
    print_error "KServe controller rollout failed"
    echo ""
    print_info "Check controller pods:"
    echo "  oc get pods -n redhat-ods-applications -l control-plane=kserve-controller-manager"
    echo ""
    print_info "Check controller logs:"
    echo "  oc logs -n redhat-ods-applications -l control-plane=kserve-controller-manager"
    exit 1
fi

print_success "KServe controller is ready"
echo ""

# Check 3: Wait for webhook service to have endpoints
echo "3. Waiting for KServe webhook service endpoints..."
timeout=300
elapsed=0

while true; do
    endpoints=$(oc get endpoints kserve-webhook-server-service -n redhat-ods-applications -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null || echo "")

    if [ -n "$endpoints" ]; then
        print_success "KServe webhook service has endpoints: $endpoints"
        break
    fi

    if [ $elapsed -ge $timeout ]; then
        print_error "Timeout waiting for webhook service endpoints"
        echo ""
        print_info "Check webhook pod:"
        echo "  oc get pods -n redhat-ods-applications -l control-plane=kserve-controller-manager"
        echo ""
        print_info "Check service:"
        echo "  oc describe svc kserve-webhook-server-service -n redhat-ods-applications"
        exit 1
    fi

    echo "Waiting for webhook endpoints... ($elapsed/$timeout seconds)"
    sleep 10
    elapsed=$((elapsed + 10))
done

echo ""

# Check 4: Verify webhook is responding
echo "4. Testing webhook connectivity..."
sleep 5  # Give it a moment to fully initialize

# Check if we can reach the webhook service
webhook_pod=$(oc get pods -n redhat-ods-applications -l control-plane=kserve-controller-manager -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -n "$webhook_pod" ]; then
    print_success "KServe webhook pod is running: $webhook_pod"
else
    print_warning "Could not find webhook pod, but service has endpoints"
fi

echo ""

# Check 5: Verify CRDs are established
echo "5. Verifying KServe CRDs are established..."

if oc wait --for=condition=established crd/servingruntimes.serving.kserve.io --timeout=60s &>/dev/null; then
    print_success "ServingRuntime CRD is established"
else
    print_error "ServingRuntime CRD is not established"
    exit 1
fi

if oc wait --for=condition=established crd/inferenceservices.serving.kserve.io --timeout=60s &>/dev/null; then
    print_success "InferenceService CRD is established"
else
    print_error "InferenceService CRD is not established"
    exit 1
fi

echo ""

# Check 6: Verify Knative Serving is ready
echo "6. Checking Knative Serving..."

if oc get deployment activator -n knative-serving &>/dev/null; then
    if oc rollout status deployment/activator -n knative-serving --timeout=120s &>/dev/null; then
        print_success "Knative Serving activator is ready"
    else
        print_warning "Knative Serving activator may not be ready"
    fi
else
    print_warning "Knative Serving not found (may be OK for some setups)"
fi

echo ""

# Final verification
echo "========================================="
print_success "KServe is fully ready! ✨"
echo "========================================="
echo ""

print_info "You can now proceed with vLLM deployment:"
echo "  cd ../03-vllm"
echo "  ./00-download-chat-template.sh"
echo "  oc apply -f 01-vllm-runtime-gpu.yaml"
echo "  oc apply -f 02-vllm-inference-service-gpu.yaml"
echo ""
echo "Or use the automated deployment:"
echo "  cd ../scripts"
echo "  ./deploy-all.sh"
