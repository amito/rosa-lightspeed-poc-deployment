#!/bin/bash
# Cleanup script for Lightspeed Stack POC deployment

set -euo pipefail

NAMESPACE="lightspeed-poc"

echo "========================================="
echo "Lightspeed Stack POC Cleanup"
echo "========================================="
echo ""

# Function to print colored output
print_success() { echo -e "\033[0;32m✅ $1\033[0m"; }
print_error() { echo -e "\033[0;31m❌ $1\033[0m"; }
print_info() { echo -e "\033[0;34mℹ️  $1\033[0m"; }
print_warning() { echo -e "\033[0;33m⚠️  $1\033[0m"; }

# Confirmation
echo "This will DELETE the following resources:"
echo "  - Namespace: $NAMESPACE"
echo "  - All pods, services, routes, and secrets in the namespace"
echo "  - vLLM InferenceService and ServingRuntime"
echo "  - Llama Stack and Lightspeed Stack deployments"
echo ""
print_warning "This action cannot be undone!"
echo ""

read -p "Are you sure you want to proceed? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    print_info "Cleanup cancelled"
    exit 0
fi

echo ""
print_info "Starting cleanup..."
echo ""

# Check if namespace exists
if ! oc get namespace $NAMESPACE &> /dev/null; then
    print_warning "Namespace $NAMESPACE does not exist. Nothing to clean up."
    exit 0
fi

# Show current resources
echo "Current resources in namespace $NAMESPACE:"
oc get all -n $NAMESPACE

echo ""
print_info "Deleting namespace $NAMESPACE..."

# Delete the namespace (this will cascade delete everything)
if oc delete namespace $NAMESPACE; then
    print_success "Namespace $NAMESPACE deleted"
else
    print_error "Failed to delete namespace $NAMESPACE"
    exit 1
fi

# Wait for namespace to be fully deleted
print_info "Waiting for namespace to be fully deleted..."
timeout=120
elapsed=0
while oc get namespace $NAMESPACE &> /dev/null; do
    if [ $elapsed -ge $timeout ]; then
        print_warning "Timeout waiting for namespace deletion. It may still be terminating."
        break
    fi
    echo "Waiting... ($elapsed/$timeout seconds)"
    sleep 5
    elapsed=$((elapsed + 5))
done

if ! oc get namespace $NAMESPACE &> /dev/null; then
    print_success "Namespace fully removed"
fi

echo ""
echo "========================================="
echo "✅ CLEANUP COMPLETE"
echo "========================================="
echo ""
print_info "All POC resources have been removed from the cluster."
