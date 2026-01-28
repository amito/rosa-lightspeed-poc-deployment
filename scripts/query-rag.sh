#!/bin/bash
# CLI tool for querying the Lightspeed Stack RAG system
#
# Usage:
#   ./query-rag.sh "Your question here"
#   ./query-rag.sh  # Interactive mode
#
# Examples:
#   ./query-rag.sh "What are the key features of RHOAI?"
#   ./query-rag.sh "How do I deploy a model in OpenShift AI?"

set -euo pipefail

NAMESPACE="lightspeed-poc"

# Color functions
print_success() { echo -e "\033[0;32m✅ $1\033[0m"; }
print_error() { echo -e "\033[0;31m❌ $1\033[0m"; }
print_info() { echo -e "\033[0;34mℹ️  $1\033[0m"; }
print_header() { echo -e "\033[1;36m$1\033[0m"; }
print_response() { echo -e "\033[0;37m$1\033[0m"; }

# Get the Route URL
get_route_url() {
    LIGHTSPEED_URL=$(oc get route lightspeed-stack -n $NAMESPACE -o jsonpath='{.spec.host}' 2>/dev/null || echo "")

    if [ -z "$LIGHTSPEED_URL" ]; then
        print_error "Could not find Lightspeed Stack route"
        print_info "Make sure the deployment is running: oc get route -n $NAMESPACE"
        exit 1
    fi

    echo "$LIGHTSPEED_URL"
}

# Send query to the RAG system
query_rag() {
    local query="$1"
    local url="$2"
    local no_tools="${3:-false}"

    local response
    response=$(curl -sk --max-time 120 -X POST "https://${url}/v1/query" \
        -H "Content-Type: application/json" \
        -d "{\"query\": \"$query\", \"no_tools\": $no_tools}" 2>&1)

    echo "$response"
}

# Format and display the response
display_response() {
    local response="$1"

    # Check if response is valid JSON
    if ! echo "$response" | jq -e '.' > /dev/null 2>&1; then
        print_error "Invalid response from server"
        echo "$response"
        return 1
    fi

    # Check for error
    if echo "$response" | jq -e '.detail' > /dev/null 2>&1; then
        print_error "Query failed"
        echo "$response" | jq -r '.detail.response // .detail' 2>/dev/null || echo "$response"
        return 1
    fi

    # Extract response text
    local answer
    answer=$(echo "$response" | jq -r '.response' 2>/dev/null)

    if [ -z "$answer" ] || [ "$answer" = "null" ]; then
        print_error "No response returned"
        echo "$response" | jq '.'
        return 1
    fi

    # Display the answer
    print_header "Response:"
    echo ""
    print_response "$answer"
    echo ""

    # Display metadata
    local input_tokens output_tokens
    input_tokens=$(echo "$response" | jq -r '.input_tokens // "N/A"' 2>/dev/null)
    output_tokens=$(echo "$response" | jq -r '.output_tokens // "N/A"' 2>/dev/null)

    if [ "$input_tokens" != "N/A" ] && [ "$input_tokens" != "null" ]; then
        print_info "Token Usage: Input=$input_tokens, Output=$output_tokens, Total=$((input_tokens + output_tokens))"
    fi

    # Display referenced documents if available
    local ref_docs
    ref_docs=$(echo "$response" | jq -r '.referenced_documents[]?' 2>/dev/null)

    if [ -n "$ref_docs" ]; then
        echo ""
        print_header "Referenced Documents:"
        echo "$response" | jq -r '.referenced_documents[] | "  • \(.document_id // "Unknown")"' 2>/dev/null || true
    fi
}

# Main function
main() {
    local query=""
    local no_tools="false"

    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --no-tools)
                no_tools="true"
                shift
                ;;
            --help|-h)
                cat <<EOF
Lightspeed Stack RAG Query Tool

Usage:
  $0 [OPTIONS] [QUERY]

Options:
  --no-tools    Disable RAG and other tools (direct LLM query only)
  --help, -h    Show this help message

Examples:
  $0 "What are the key features of RHOAI?"
  $0 "How do I deploy a model?"
  $0 --no-tools "What is Kubernetes?"
  $0  # Interactive mode

EOF
                exit 0
                ;;
            *)
                query="$1"
                shift
                ;;
        esac
    done

    # Header
    print_header "════════════════════════════════════════"
    print_header "  Lightspeed Stack RAG Query Tool"
    print_header "════════════════════════════════════════"
    echo ""

    # Get route URL
    print_info "Connecting to Lightspeed Stack..."
    LIGHTSPEED_URL=$(get_route_url)
    print_success "Connected to: https://$LIGHTSPEED_URL"
    echo ""

    # Interactive mode if no query provided
    if [ -z "$query" ]; then
        print_info "Enter your query (or 'quit' to exit):"
        echo ""
        while true; do
            echo -n "> "
            read -r query

            if [ -z "$query" ]; then
                continue
            fi

            if [ "$query" = "quit" ] || [ "$query" = "exit" ]; then
                print_info "Goodbye!"
                exit 0
            fi

            echo ""
            print_info "Querying RAG system..."
            response=$(query_rag "$query" "$LIGHTSPEED_URL" "$no_tools")
            echo ""
            display_response "$response"
            echo ""
            print_info "Enter another query (or 'quit' to exit):"
            echo ""
        done
    else
        # Single query mode
        print_info "Query: $query"
        echo ""
        print_info "Querying RAG system..."
        response=$(query_rag "$query" "$LIGHTSPEED_URL" "$no_tools")
        echo ""
        display_response "$response"
        echo ""
    fi
}

main "$@"
