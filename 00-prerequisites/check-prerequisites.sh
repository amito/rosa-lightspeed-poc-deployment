#!/bin/bash
# Script to check prerequisites for Lightspeed Stack + vLLM deployment

set -euo pipefail

echo "========================================="
echo "Checking Prerequisites"
echo "========================================="
echo ""

# Function to print colored output
print_success() { echo -e "\033[0;32m✅ $1\033[0m"; }
print_error() { echo -e "\033[0;31m❌ $1\033[0m"; }
print_info() { echo -e "\033[0;34mℹ️  $1\033[0m"; }
print_warning() { echo -e "\033[0;33m⚠️  $1\033[0m"; }

HAS_ERRORS=0

# Check 1: OC CLI
echo "1. Checking OpenShift CLI..."
if command -v oc &> /dev/null; then
    print_success "oc CLI is installed ($(oc version --client | head -n1))"
else
    print_error "oc CLI is not installed"
    echo "  Install from: https://mirror.openshift.com/pub/openshift-v4/clients/ocp/"
    HAS_ERRORS=1
fi
echo ""

# Check 2: Cluster connection
echo "2. Checking cluster connection..."
if oc whoami &> /dev/null; then
    print_success "Connected to cluster: $(oc whoami --show-server)"
    print_info "Logged in as: $(oc whoami)"
else
    print_error "Not connected to an OpenShift cluster"
    echo "  Run: oc login <cluster-url>"
    HAS_ERRORS=1
fi
echo ""

# Check 3: GPU nodes
echo "3. Checking for GPU nodes..."
gpu_nodes=$(oc get nodes -l nvidia.com/gpu.present=true --no-headers 2>/dev/null | wc -l)
if [ "$gpu_nodes" -gt 0 ]; then
    print_success "Found $gpu_nodes GPU node(s)"
    oc get nodes -l nvidia.com/gpu.present=true -o custom-columns=NAME:.metadata.name,GPU:.status.capacity.nvidia\\.com/gpu,INSTANCE:.metadata.labels.node\\.kubernetes\\.io/instance-type
else
    print_error "No GPU nodes found"
    echo "  This cluster needs GPU nodes for vLLM deployment"
    echo "  For ROSA: https://docs.openshift.com/rosa/rosa_cluster_admin/rosa_nodes/rosa-managing-worker-nodes.html"
    HAS_ERRORS=1
fi
echo ""

# Check 4: NVIDIA GPU Operator
echo "4. Checking NVIDIA GPU Operator..."
if oc get csv -A 2>/dev/null | grep -q nvidia-gpu-operator; then
    print_success "NVIDIA GPU Operator is installed"
    oc get csv -A | grep nvidia-gpu-operator | head -n1
else
    print_warning "NVIDIA GPU Operator not found"
    echo "  Install from OperatorHub if you have GPU nodes"
fi
echo ""

# Check 5: Red Hat OpenShift AI Operator
echo "5. Checking Red Hat OpenShift AI Operator..."
if oc get csv -n redhat-ods-operator 2>/dev/null | grep -q rhods-operator; then
    print_success "RHOAI Operator is installed"
    oc get csv -n redhat-ods-operator | grep rhods-operator | head -n1
else
    print_error "RHOAI Operator not found"
    echo "  This is REQUIRED for KServe and vLLM deployment"
    echo "  Install from OperatorHub: Red Hat OpenShift AI"
    HAS_ERRORS=1
fi
echo ""

# Check 6: DataScienceCluster
echo "6. Checking DataScienceCluster..."
if oc get datasciencecluster 2>/dev/null | grep -q default-dsc; then
    print_success "DataScienceCluster exists"
    oc get datasciencecluster
else
    print_error "DataScienceCluster not found"
    echo "  Create a DataScienceCluster after installing RHOAI operator"
    echo "  See: ./00-prerequisites/setup-rhoai.md"
    HAS_ERRORS=1
fi
echo ""

# Check 7: KServe CRDs
echo "7. Checking KServe CRDs..."
kserve_crds=0
if oc get crd servingruntimes.serving.kserve.io &> /dev/null; then
    print_success "ServingRuntime CRD exists"
    ((kserve_crds++))
else
    print_error "ServingRuntime CRD not found"
fi

if oc get crd inferenceservices.serving.kserve.io &> /dev/null; then
    print_success "InferenceService CRD exists"
    ((kserve_crds++))
else
    print_error "InferenceService CRD not found"
fi

if [ $kserve_crds -eq 2 ]; then
    print_success "All required KServe CRDs are installed"
else
    print_error "KServe CRDs are missing"
    echo "  These are created by the DataScienceCluster with KServe enabled"
    echo "  See: ./00-prerequisites/setup-rhoai.md"
    HAS_ERRORS=1
fi
echo ""

# Check 8: HuggingFace Token
echo "8. Checking HuggingFace Token..."
if [ -n "${HF_TOKEN:-}" ]; then
    print_success "HF_TOKEN environment variable is set"
else
    print_warning "HF_TOKEN environment variable is not set"
    echo "  You'll need this for model downloads"
    echo "  Get a token from: https://huggingface.co/settings/tokens"
    echo "  Then: export HF_TOKEN='your_token_here'"
fi
echo ""

# Summary
echo "========================================="
if [ $HAS_ERRORS -eq 0 ]; then
    print_success "All prerequisites are met! ✨"
    echo ""
    echo "You can proceed with deployment:"
    echo "  cd ../scripts"
    echo "  ./deploy-all.sh"
else
    print_error "Some prerequisites are missing"
    echo ""
    echo "Please address the errors above before deploying."
    echo "See: ./00-prerequisites/setup-rhoai.md for RHOAI setup"
fi
echo "========================================="

exit $HAS_ERRORS
