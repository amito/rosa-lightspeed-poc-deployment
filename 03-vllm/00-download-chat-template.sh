#!/bin/bash
# This script downloads the chat template for Llama 3.2 and creates a ConfigMap

set -euo pipefail

NAMESPACE="lightspeed-poc"
TEMPLATE_URL="https://raw.githubusercontent.com/vllm-project/vllm/main/examples/tool_chat_template_llama3.2_json.jinja"

echo "Downloading chat template..."
curl -sL -o tool_chat_template_llama3.2_json.jinja "$TEMPLATE_URL" || {
    echo "❌ Failed to download jinja template"
    exit 1
}

echo "Creating ConfigMap..."
oc create configmap vllm-chat-template \
    -n "$NAMESPACE" \
    --from-file=tool_chat_template_llama3.2_json.jinja \
    --dry-run=client -o yaml | oc apply -f -

echo "✅ Chat template ConfigMap created"
echo "Cleaning up downloaded file..."
rm -f tool_chat_template_llama3.2_json.jinja

echo "✅ Done"
