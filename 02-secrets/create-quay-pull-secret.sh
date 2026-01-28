#!/bin/bash
# Script to create Red Hat Quay.io pull secret for vLLM image

set -euo pipefail

NAMESPACE="lightspeed-poc"

echo "========================================="
echo "Create Red Hat Quay.io Pull Secret"
echo "========================================="
echo ""

# Function to print colored output
print_success() { echo -e "\033[0;32m✅ $1\033[0m"; }
print_error() { echo -e "\033[0;31m❌ $1\033[0m"; }
print_info() { echo -e "\033[0;34mℹ️  $1\033[0m"; }

# Check if namespace exists
if ! oc get namespace $NAMESPACE &> /dev/null; then
    print_error "Namespace $NAMESPACE does not exist"
    echo "Create it first: oc apply -f ../01-namespace/namespace.yaml"
    exit 1
fi

# Option 1: Use environment variables
if [ -n "${QUAY_USERNAME:-}" ] && [ -n "${QUAY_PASSWORD:-}" ]; then
    print_info "Using credentials from environment variables"
    USERNAME="$QUAY_USERNAME"
    PASSWORD="$QUAY_PASSWORD"
else
    # Option 2: Prompt for credentials
    echo "Enter your Red Hat Quay.io credentials"
    echo "Get them from: https://access.redhat.com/terms-based-registry/"
    echo ""

    read -p "Quay.io Username: " USERNAME
    read -sp "Quay.io Password/Token: " PASSWORD
    echo ""
fi

if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
    print_error "Username and password/token are required"
    exit 1
fi

echo ""
print_info "Creating pull secret..."

# Create the secret
oc create secret docker-registry rh-quay-pull-secret \
    --docker-server=quay.io \
    --docker-username="$USERNAME" \
    --docker-password="$PASSWORD" \
    -n $NAMESPACE \
    --dry-run=client -o yaml | oc apply -f -

if [ $? -eq 0 ]; then
    print_success "Pull secret created: rh-quay-pull-secret"
else
    print_error "Failed to create pull secret"
    exit 1
fi

echo ""
print_info "Linking secret to default service account..."

# Link to default service account for automatic image pulls
oc secrets link default rh-quay-pull-secret --for=pull -n $NAMESPACE 2>/dev/null || print_info "Secret already linked or link failed (may be OK if already linked)"

echo ""
print_success "Quay.io pull secret is configured! ✨"
echo ""
print_info "You can now deploy vLLM with the Red Hat image:"
echo "  cd ../03-vllm"
echo "  oc apply -f 01-vllm-runtime-gpu.yaml"
echo "  oc apply -f 02-vllm-inference-service-gpu.yaml"
