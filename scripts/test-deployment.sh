#!/bin/bash
# Test script for Lightspeed Stack POC deployment

set -euo pipefail

NAMESPACE="lightspeed-poc"

echo "========================================="
echo "Testing Lightspeed Stack Deployment"
echo "========================================="
echo ""

# Function to print colored output
print_success() { echo -e "\033[0;32m✅ $1\033[0m"; }
print_error() { echo -e "\033[0;31m❌ $1\033[0m"; }
print_info() { echo -e "\033[0;34mℹ️  $1\033[0m"; }
print_test() { echo -e "\033[0;36m🧪 $1\033[0m"; }

# Get the Route URL
LIGHTSPEED_URL=$(oc get route lightspeed-stack -n $NAMESPACE -o jsonpath='{.spec.host}' 2>/dev/null || echo "")

if [ -z "$LIGHTSPEED_URL" ]; then
    print_error "Could not find Lightspeed Stack route"
    exit 1
fi

print_info "Testing Lightspeed Stack at: https://${LIGHTSPEED_URL}"
echo ""

# Test 1: Health endpoints
echo "Test 1: Health Endpoints"
echo "-------------------------"

print_test "Testing liveness endpoint..."
response=$(curl -sk -w "%{http_code}" "https://${LIGHTSPEED_URL}/liveness" -o /dev/null)
if [ "$response" = "200" ]; then
    print_success "Liveness check passed"
else
    print_error "Liveness check failed (HTTP $response)"
fi

print_test "Testing readiness endpoint..."
response=$(curl -sk -w "%{http_code}" "https://${LIGHTSPEED_URL}/readiness" -o /dev/null)
if [ "$response" = "200" ]; then
    print_success "Readiness check passed"
else
    print_error "Readiness check failed (HTTP $response)"
fi

echo ""

# Test 2: Info endpoint
echo "Test 2: Service Info"
echo "--------------------"

print_test "Getting service information..."
info=$(curl -sk "https://${LIGHTSPEED_URL}/v1/info")
if echo "$info" | jq -e '.name' > /dev/null 2>&1; then
    print_success "Service info retrieved successfully"
    echo "$info" | jq .
else
    print_error "Failed to get service info"
fi

echo ""

# Test 3: Models endpoint
echo "Test 3: Available Models"
echo "------------------------"

print_test "Listing available models..."
models=$(curl -sk "https://${LIGHTSPEED_URL}/v1/models")
if echo "$models" | jq -e '.models' > /dev/null 2>&1; then
    model_count=$(echo "$models" | jq '.models | length')
    print_success "Found $model_count models"
    echo "$models" | jq '.models[] | {identifier, model_type}'
else
    print_error "Failed to list models"
fi

echo ""

# Test 4: Basic query (no RAG)
echo "Test 4: Basic Query (No RAG)"
echo "-----------------------------"

print_test "Sending basic query (may take up to 3 minutes)..."
query_response=$(curl -sk --max-time 200 -X POST "https://${LIGHTSPEED_URL}/v1/query" \
    -H "Content-Type: application/json" \
    -d '{"query": "What is Kubernetes in one sentence?", "system_prompt": "You are a helpful assistant. Answer concisely in one sentence.", "no_tools": true}')

if echo "$query_response" | jq -e '.response' > /dev/null 2>&1; then
    print_success "Basic query successful"
    echo "Response:"
    echo "$query_response" | jq -r '.response' | head -c 200
    echo "..."
else
    print_error "Basic query failed"
    echo "Response:"
    echo "$query_response"
fi

echo ""
echo ""

# Test 5: RAG query
echo "Test 5: RAG Query (Knowledge Search)"
echo "-------------------------------------"

print_test "Sending RAG query about RHOAI (may take up to 3 minutes)..."
rag_query='What are the key features of Red Hat OpenShift AI?'

rag_response=$(curl -sk --max-time 200 -X POST "https://${LIGHTSPEED_URL}/v1/query" \
    -H "Content-Type: application/json" \
    -d "{\"query\": \"$rag_query\", \"no_tools\": false}")

if echo "$rag_response" | jq -e '.response' > /dev/null 2>&1; then
    print_success "RAG query successful"
    echo "Response:"
    echo "$rag_response" | jq -r '.response' | head -c 300
    echo "..."

    # Check if RAG was actually used (look for common RAG-related terms in response)
    if echo "$rag_response" | jq -r '.response' | grep -qi "jupyter\|model serving\|pipeline\|gpu"; then
        print_success "Response appears to use RAG data (mentions RHOAI features)"
    else
        print_info "Response may not be using RAG data - check Llama Stack logs"
    fi
else
    print_error "RAG query failed"
    echo "Response:"
    echo "$rag_response"
fi

echo ""
echo ""

# Test 6: Streaming query
echo "Test 6: Streaming Query"
echo "-----------------------"

print_test "Testing streaming endpoint..."
stream_response=$(curl -sk --max-time 200 -X POST "https://${LIGHTSPEED_URL}/v1/streaming_query" \
    -H "Content-Type: application/json" \
    -d '{"query": "List three benefits of using Red Hat OpenShift AI", "no_tools": false}' 2>/dev/null | head -n 20)

if [ -n "$stream_response" ]; then
    print_success "Streaming query successful"
    echo "First few chunks:"
    echo "$stream_response"
else
    print_error "Streaming query failed"
fi

echo ""
echo ""

# Test 7: Pod status
echo "Test 7: Pod Health"
echo "------------------"

print_test "Checking all pods..."
pods=$(oc get pods -n $NAMESPACE --no-headers)

echo "$pods" | while read -r line; do
    pod_name=$(echo "$line" | awk '{print $1}')
    pod_status=$(echo "$line" | awk '{print $3}')
    pod_ready=$(echo "$line" | awk '{print $2}')

    if [ "$pod_status" = "Running" ] && [[ "$pod_ready" =~ ^[1-9]/[1-9] ]]; then
        print_success "Pod $pod_name is healthy ($pod_ready, $pod_status)"
    else
        print_error "Pod $pod_name may have issues ($pod_ready, $pod_status)"
    fi
done

echo ""
echo "========================================="
echo "✅ TESTING COMPLETE"
echo "========================================="
echo ""

print_info "Access the web UI at:"
echo "  https://${LIGHTSPEED_URL}"
echo ""
print_info "Swagger UI:"
echo "  https://${LIGHTSPEED_URL}/docs"
echo ""
print_info "API Documentation:"
echo "  https://${LIGHTSPEED_URL}/redoc"
