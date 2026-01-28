#!/bin/bash
# Script to check available vLLM image tags

set -euo pipefail

echo "========================================="
echo "Checking Available vLLM Image Tags"
echo "========================================="
echo ""

print_info() { echo -e "\033[0;34mℹ️  $1\033[0m"; }
print_success() { echo -e "\033[0;32m✅ $1\033[0m"; }
print_error() { echo -e "\033[0;31m❌ $1\033[0m"; }

# Check if you have access to Red Hat registry
if [ -n "${QUAY_USERNAME:-}" ] && [ -n "${QUAY_PASSWORD:-}" ]; then
    print_info "Attempting to list Red Hat vLLM image tags..."
    echo ""

    # Try to get tags from Red Hat registry using skopeo (if available)
    if command -v skopeo &> /dev/null; then
        echo "Using skopeo to list tags..."
        skopeo list-tags docker://quay.io/modh/vllm \
            --creds "${QUAY_USERNAME}:${QUAY_PASSWORD}" 2>/dev/null || {
            print_error "Failed to list tags from quay.io/modh/vllm"
            echo "This could mean:"
            echo "  1. You don't have access to this repository"
            echo "  2. The repository path is different"
            echo "  3. Your credentials are incorrect"
        }
    else
        print_info "skopeo not installed. Install with: sudo dnf install skopeo"
        echo ""
        print_info "Alternatively, check available tags at:"
        echo "  https://quay.io/repository/modh/vllm?tab=tags"
        echo "  (Login required)"
    fi
else
    print_info "QUAY_USERNAME or QUAY_PASSWORD not set"
    echo "To check Red Hat images, set your credentials:"
    echo "  export QUAY_USERNAME='your_username'"
    echo "  export QUAY_PASSWORD='your_password'"
fi

echo ""
echo "========================================="
echo "Recommended Images"
echo "========================================="
echo ""

echo "Public vLLM Images (No authentication needed):"
echo "  docker.io/vllm/vllm-openai:latest"
echo "  docker.io/vllm/vllm-openai:v0.6.3.post1"
echo "  docker.io/vllm/vllm-openai:v0.6.0"
echo ""

echo "Common Red Hat vLLM Image Tags (if you have access):"
echo "  quay.io/modh/vllm:stable"
echo "  quay.io/modh/vllm:fast"
echo "  quay.io/modh/vllm:rhoai-2.14"
echo "  quay.io/modh/vllm:rhoai-2.13"
echo ""

echo "To test if an image is accessible:"
echo "  podman pull docker.io/vllm/vllm-openai:v0.6.3.post1"
echo ""
echo "Or if you have Quay credentials:"
echo "  podman login quay.io"
echo "  podman pull quay.io/modh/vllm:stable"
