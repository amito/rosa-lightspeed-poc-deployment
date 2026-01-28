# Lightspeed Stack Deployment

Lightspeed Stack is the user-facing API service that provides:
- REST API for querying the LLM
- Integration with Llama Stack for agent orchestration and RAG
- User data collection (feedback, transcripts)
- Web UI for testing

## Prerequisites

- Llama Stack must be deployed and running (see `../04-llama-stack/`)
- vLLM must be deployed and running (see `../03-vllm/`)
- Namespace and secrets created (see `../01-namespace/` and `../02-secrets/`)

## Deployment Steps

### 1. Create Lightspeed Stack ConfigMap

```bash
oc apply -f 01-lightspeed-stack-configmap.yaml
```

This creates a ConfigMap with the `lightspeed-stack.yaml` configuration that:
- Connects to the Llama Stack service
- Configures CORS for web UI access
- Enables user data collection
- Sets up a custom system prompt optimized for RHOAI questions

### 2. Deploy Lightspeed Stack Pod, Service, and Route

```bash
oc apply -f 02-lightspeed-stack-deployment.yaml
```

This creates:
- **Pod**: Runs the lightspeed-stack application
- **Service**: Exposes the pod within the cluster
- **Route**: Creates an external URL for accessing the service

### 3. Verify Deployment

Wait for the pod to be ready:

```bash
oc get pods -n lightspeed-poc -w
```

Check pod logs:

```bash
oc logs -f lightspeed-stack-service -n lightspeed-poc
```

You should see logs indicating:
- Server starting on port 8080
- Loading configuration
- Connecting to Llama Stack
- Server ready to accept requests

### 4. Get the Route URL

```bash
LIGHTSPEED_URL=$(oc get route lightspeed-stack -n lightspeed-poc -o jsonpath='{.spec.host}')
echo "Lightspeed Stack URL: https://${LIGHTSPEED_URL}"
```

## Testing the Deployment

### Access the Web UI

Open your browser to the Route URL:

```bash
echo "https://$(oc get route lightspeed-stack -n lightspeed-poc -o jsonpath='{.spec.host}')"
```

You should see the Lightspeed Stack front page with links to:
- Swagger UI (`/docs`)
- ReDoc API documentation (`/redoc`)
- Health endpoints

### Test with curl

Get the route URL:

```bash
LIGHTSPEED_URL=$(oc get route lightspeed-stack -n lightspeed-poc -o jsonpath='{.spec.host}')
```

Test the info endpoint:

```bash
curl https://${LIGHTSPEED_URL}/v1/info
```

Expected response:
```json
{
  "name": "Lightspeed Core Service - ROSA POC",
  "version": "X.Y.Z"
}
```

List available models:

```bash
curl https://${LIGHTSPEED_URL}/v1/models
```

Send a query without RAG:

```bash
curl -X POST "https://${LIGHTSPEED_URL}/v1/query" \
  -H "Content-Type: application/json" \
  -d '{
    "query": "What is Kubernetes?",
    "system_prompt": "You are a helpful assistant."
  }'
```

### Test RAG Functionality

Send a query that should trigger RAG:

```bash
curl -X POST "https://${LIGHTSPEED_URL}/v1/query" \
  -H "Content-Type: application/json" \
  -d '{
    "query": "What are the key features of Red Hat OpenShift AI?",
    "no_tools": false
  }' | jq .
```

With the default system prompt (configured in the ConfigMap), the assistant should use the `knowledge_search` tool to retrieve information from the RAG database before answering.

Test inference-specific questions:

```bash
curl -X POST "https://${LIGHTSPEED_URL}/v1/query" \
  -H "Content-Type: application/json" \
  -d '{
    "query": "How do I deploy a model for inference in RHOAI using vLLM?",
    "no_tools": false
  }' | jq .
```

### Test Streaming Query

```bash
curl -X POST "https://${LIGHTSPEED_URL}/v1/streaming-query" \
  -H "Content-Type: application/json" \
  -d '{
    "query": "Explain the different model serving options in Red Hat OpenShift AI",
    "no_tools": false
  }'
```

## Configuration Details

### lightspeed-stack.yaml

Key configuration sections:

1. **Service Configuration**:
   - Listens on `0.0.0.0:8080`
   - Authentication disabled (for POC)
   - CORS enabled for web UI

2. **Llama Stack Connection**:
   - URL: `http://llama-stack-service.lightspeed-poc.svc.cluster.local:8321`
   - Uses library client mode: `false` (connects as external server)

3. **System Prompt**:
   - Optimized for RHOAI questions
   - Instructs the model to use `knowledge_search` tool for documentation queries
   - Configured to be helpful and accurate

4. **User Data Collection**:
   - Feedback storage enabled
   - Transcripts storage enabled
   - Data stored in ephemeral volumes (for POC)

### External Access

The Route creates an HTTPS endpoint that:
- Uses Edge TLS termination
- Redirects HTTP to HTTPS
- Accessible from outside the cluster

## API Endpoints

### Health Endpoints

- `/v1/liveness` - Liveness probe
- `/v1/readiness` - Readiness probe (checks provider health)

### Information Endpoints

- `/v1/info` - Service information
- `/v1/models` - List available models

### Query Endpoints

- `/v1/query` - Send a query (non-streaming)
- `/v1/streaming-query` - Send a query (streaming response)

### Documentation

- `/docs` - Swagger UI
- `/redoc` - ReDoc documentation
- `/openapi.json` - OpenAPI specification

## Troubleshooting

### Pod Not Starting

Check events:
```bash
oc describe pod lightspeed-stack-service -n lightspeed-poc
```

Common issues:
- ConfigMap not found
- Image pull issues
- Resource constraints

### Cannot Connect to Llama Stack

Check Llama Stack service:
```bash
oc get svc llama-stack-service -n lightspeed-poc
```

Test connection from within the pod:
```bash
oc exec lightspeed-stack-service -n lightspeed-poc -- \
  curl -s http://llama-stack-service.lightspeed-poc.svc.cluster.local:8321/v1/version
```

### Readiness Probe Failing

Check logs:
```bash
oc logs lightspeed-stack-service -n lightspeed-poc
```

The readiness probe checks if all LLM providers are healthy. If vLLM or Llama Stack are not ready, the readiness probe will fail.

### RAG Not Working

Verify the query includes tool usage:
- Check that `no_tools` is not set to `true`
- Verify the system prompt instructs the model to use `knowledge_search`
- Check Llama Stack logs for RAG tool calls

### Route Not Accessible

Verify the route was created:
```bash
oc get route lightspeed-stack -n lightspeed-poc
```

Check route details:
```bash
oc describe route lightspeed-stack -n lightspeed-poc
```

## Monitoring

View real-time logs:
```bash
oc logs -f lightspeed-stack-service -n lightspeed-poc
```

Monitor pod resource usage:
```bash
oc adm top pod lightspeed-stack-service -n lightspeed-poc
```

## Next Steps

Once Lightspeed Stack is running:

1. Test the complete RAG flow with various queries
2. Monitor performance and response times
3. Review collected feedback and transcripts (if enabled)
4. Consider adding authentication for production use
5. Set up persistent storage for user data
6. Configure monitoring and alerting
7. Test with realistic workloads
