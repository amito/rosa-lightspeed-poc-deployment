# Secrets Setup

This directory contains templates for creating the required secrets.

## Required Secrets

### 1. HuggingFace Token (for model downloads)

Create a secret with your HuggingFace token:

```bash
oc create secret generic hf-token-secret \
  --from-literal=token=YOUR_HUGGINGFACE_TOKEN \
  -n lightspeed-poc
```

To get a HuggingFace token:
1. Sign up at https://huggingface.co
2. Go to Settings → Access Tokens
3. Create a new token with read access

### 2. vLLM API Key

Create a secret for vLLM API authentication:

```bash
oc create secret generic vllm-api-key-secret \
  --from-literal=key=YOUR_VLLM_API_KEY \
  -n lightspeed-poc
```

For POC purposes, you can use a simple key:
```bash
oc create secret generic vllm-api-key-secret \
  --from-literal=key="poc-key-12345" \
  -n lightspeed-poc
```

### 3. (Optional) OpenAI API Key

If you want to use OpenAI as fallback or for comparison:

```bash
oc create secret generic openai-api-key-secret \
  --from-literal=key=YOUR_OPENAI_API_KEY \
  -n lightspeed-poc
```

## Verify Secrets

```bash
oc get secrets -n lightspeed-poc
```

## 4. (Required for Red Hat vLLM Image) Quay.io Pull Secret

The vLLM deployment uses the Red Hat-provided image from `quay.io/modh/vllm` which requires authentication.

### Option A: Use the Script (Recommended)

```bash
# Set credentials as environment variables
export QUAY_USERNAME="your_username"
export QUAY_PASSWORD="your_password_or_token"

# Run the script
./create-quay-pull-secret.sh
```

Or the script will prompt you for credentials interactively if environment variables are not set.

### Option B: Manual Creation

```bash
oc create secret docker-registry rh-quay-pull-secret \
  --docker-server=quay.io \
  --docker-username='<your-username>' \
  --docker-password='<your-password-or-token>' \
  -n lightspeed-poc

# Link to service account
oc secrets link default rh-quay-pull-secret --for=pull -n lightspeed-poc
```

### Getting Quay.io Credentials

1. Go to: https://access.redhat.com/terms-based-registry/
2. Login with your Red Hat account
3. Generate a new registry service account or use existing one
4. Copy the username and password/token

## Create All Secrets at Once

```bash
# Set your tokens as environment variables first
export HF_TOKEN="your_huggingface_token"
export VLLM_API_KEY="poc-key-12345"
export QUAY_USERNAME="your_quay_username"
export QUAY_PASSWORD="your_quay_password"

# Create all secrets
oc create secret generic hf-token-secret --from-literal=token="${HF_TOKEN}" -n lightspeed-poc
oc create secret generic vllm-api-key-secret --from-literal=key="${VLLM_API_KEY}" -n lightspeed-poc
./create-quay-pull-secret.sh
```
