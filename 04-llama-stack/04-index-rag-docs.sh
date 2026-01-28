#!/bin/bash
# Script to index sample RHOAI documentation into the RAG vector database
# This script should be run AFTER deploying llama-stack with the sample-docs ConfigMap

set -euo pipefail

NAMESPACE="lightspeed-poc"
VECTOR_DB_ID="rhoai-docs"

echo "========================================="
echo "Indexing RAG Documentation"
echo "========================================="
echo ""

# Check if llama-stack pod is running
echo "Checking llama-stack pod status..."
POD_NAME=$(oc get pods -n $NAMESPACE -l app=llama-stack -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$POD_NAME" ]; then
    echo "❌ Error: No llama-stack pod found"
    echo "Please ensure the deployment is running: oc get pods -n $NAMESPACE -l app=llama-stack"
    exit 1
fi

POD_STATUS=$(oc get pod $POD_NAME -n $NAMESPACE -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")

if [ "$POD_STATUS" != "Running" ]; then
    echo "❌ Error: llama-stack pod is not running (status: $POD_STATUS)"
    echo "Please ensure the pod is deployed and running before indexing documents."
    exit 1
fi

echo "✅ llama-stack pod $POD_NAME is running"
echo ""

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Copy sample documents to pod
echo "Copying sample documents to pod..."
oc exec $POD_NAME -n $NAMESPACE -- mkdir -p /tmp/sample-docs
oc cp "${SCRIPT_DIR}/sample-docs/." $POD_NAME:/tmp/sample-docs/ -n $NAMESPACE

echo "✅ Documents copied"
echo ""

# Copy Python indexing script to pod
echo "Copying indexing script to pod..."
oc cp "${SCRIPT_DIR}/index_rag_docs.py" $POD_NAME:/tmp/index_rag_docs.py -n $NAMESPACE

echo "✅ Script copied"
echo ""

echo "Running indexing script (this may take a few minutes)..."
echo ""

oc exec $POD_NAME -n $NAMESPACE -- python3 /tmp/index_rag_docs.py

# Cleanup temporary files from pod
echo ""
echo "Cleaning up temporary files..."
oc exec $POD_NAME -n $NAMESPACE -- rm -rf /tmp/sample-docs /tmp/index_rag_docs.py

echo "✅ Cleanup complete"

echo ""
echo "========================================="
echo "✅ RAG Indexing Complete!"
echo "========================================="
echo ""
echo "Next steps:"
echo "1. Test with: curl -X POST https://\${LIGHTSPEED_URL}/v1/query \\"
echo "              -H 'Content-Type: application/json' \\"
echo "              -d '{\"query\": \"What are the key features of RHOAI?\"}'"
echo ""
echo "2. Or run the test script: cd ../scripts && ./test-deployment.sh"
echo ""
