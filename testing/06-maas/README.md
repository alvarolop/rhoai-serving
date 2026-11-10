# MaaS (Models-as-a-Service) Testing

This directory contains scripts to test and interact with models deployed via OpenShift AI MaaS (Models-as-a-Service).

## Prerequisites

- `oc` or `kubectl` CLI
- `curl`
- `jq` (optional, for formatted output)
- Access to an OpenShift cluster with MaaS configured
- A MaaS MaaSSubscription with deployed models

## Scripts

### 1. retrieve-api-key.sh

**Creates** a new API key for a MaaS subscription using the MaaS API.

Follows the [official MaaS validation pattern](https://opendatahub-io.github.io/models-as-a-service/0.0.1/install/validation/):
- Authenticates with your OpenShift token (`oc whoami -t`)
- Calls the MaaS API to create a new API key
- API key expires in 1 month (30 days) by default

**Auto-detects:**
- **MaaS endpoint** - Queries cluster domain, tries `https://maas.<cluster-domain>`, falls back to `https://gateway.<cluster-domain>`

**Default subscription:** `basic-models` (override with `--subscription`)

**Usage:**
```bash
./testing/06-maas/retrieve-api-key.sh [OPTIONS]
```

**Options:**
- `--subscription, -s NAME` - MaaS subscription name (default: `basic-models`)

**Examples:**
```bash
# Use default subscription (basic-models)
./testing/06-maas/retrieve-api-key.sh

# Use specific subscription
./testing/06-maas/retrieve-api-key.sh --subscription my-subscription
./testing/06-maas/retrieve-api-key.sh -s my-subscription

# Override MaaS URL
MAAS_URL=https://maas.example.com ./testing/06-maas/retrieve-api-key.sh
```

**Environment Variables:**
- `MAAS_URL` - Full MaaS URL (optional). If not set, auto-detects from cluster.

**Important Notes:**
- **API key shown only once** - The plaintext API key is returned only at creation time. Store it securely.
- **Requires authentication** - You must be logged into OpenShift (`oc login`)
- **Creates new key each time** - Each run creates a new API key with 1-month expiration

**Output:**
```bash
export MAAS_API_KEY='sk-abc123...'
export MAAS_URL='https://maas.example.com'
```

To use in your shell:
```bash
eval "$(./testing/06-maas/retrieve-api-key.sh | grep '^export')"
```

### 2. send-message.sh

Send a simple message to the MaaS API (OpenAI-compatible chat completion).

**Auto-detects MaaS endpoint** from the cluster by default.

**API Key Priority:**
1. Third parameter (if provided)
2. `MAAS_API_KEY` environment variable (if set)
3. Error if neither is available

**Usage:**
```bash
./testing/06-maas/send-message.sh --message "MESSAGE" [OPTIONS]
```

**Options:**
- `--message, -m MESSAGE` - Message to send (required)
- `--model MODEL` - Model to use (auto-selects if not provided)
- `--api-key KEY` - API key (uses MAAS_API_KEY env var if not provided)
- `--max-tokens NUM` - Maximum tokens (default: 500)

**Examples:**
```bash
# Using environment variable (recommended)
eval "$(./testing/06-maas/retrieve-api-key.sh | grep '^export')"
./testing/06-maas/send-message.sh --message "What is the capital of France?"

# With short flags
./testing/06-maas/send-message.sh -m "Hello world" --model mistralai/Devstral-Small-2-24B-Instruct-2512

# With max tokens and API key
./testing/06-maas/send-message.sh -m "Tell me a story" --max-tokens 1000 --api-key sk-abc123

# Auto-select model (uses first available)
export MAAS_API_KEY=sk-abc123
./testing/06-maas/send-message.sh -m "Count to 5"
```

**Environment Variables:**
- `MAAS_API_KEY` - API key (used if not provided as parameter)
- `MAAS_URL` - Full MaaS URL (optional, auto-detects from cluster if not set)

## Quick Start

1. Get your API key:
```bash
eval "$(./testing/06-maas/retrieve-api-key.sh | grep '^export')"
echo $MAAS_API_KEY
```

2. Send messages:
```bash
./testing/06-maas/send-message.sh -m "What is the capital of France?"
./testing/06-maas/send-message.sh -m "Explain quantum computing in simple terms"
```

### Direct curl Commands

1. Retrieve API key:
```bash
API_KEY=$(./testing/06-maas/retrieve-api-key.sh | grep "export MAAS_API_KEY" | cut -d"'" -f2)
MAAS_URL="https://maas.opentlc.com"
```

2. List models:
```bash
curl -H "Authorization: Bearer $API_KEY" \
  "${MAAS_URL}/v1/models" | jq '.'
```

3. Send a chat completion:
```bash
curl -X POST \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "mistralai/Devstral-Small-2-24B-Instruct-2512",
    "messages": [
      {"role": "user", "content": "What is 2+2?"}
    ],
    "max_tokens": 100
  }' \
  "${MAAS_URL}/v1/chat/completions" | jq '.choices[0].message.content'
```

## Supported Models

The scripts work with any model deployed in your MaaS MaaSSubscription. Common examples:

- **mistralai/Devstral-Small-2-24B-Instruct-2512** - Agentic coding model with tool calling
- **mistralai/Mistral-Small-Instruct-2409** - General-purpose chat model
- **ibm-granite/granite-guardian-4.1-8b** - Guardrails/moderation model
- **meta-llama/Llama-3.1-8B-Instruct** - Meta's instruction-tuned model

## Troubleshooting

### API Key Not Found

```bash
Error: No API key secret found in MaaSSubscription status
```

**Solution:** Check if the MaaSSubscription has a valid API key:
```bash
oc get MaaSSubscription my-MaaSSubscription -o yaml | grep -A 5 apiKeySecret
```

### Models Not Listed

```bash
No models found
```

**Solution:** Verify models are deployed and associated with the MaaSSubscription:
```bash
oc get llminferenceservice --all-namespaces
oc get MaaSSubscription my-MaaSSubscription -o yaml | grep -A 10 models
```

### Connection Refused

```bash
curl: (7) Failed to connect to maas.opentlc.com port 8080
```

**Solution:** Check the correct MaaS host and port:
```bash
# Try different ports
PORT=443 ./testing/06-maas/retrieve-api-key.sh my-MaaSSubscription
PORT=8443 ./testing/06-maas/retrieve-api-key.sh my-MaaSSubscription

# Check ingress/route
oc get route -n openshift-ingress | grep maas
```

## API Reference

The MaaS API is OpenAI-compatible. Full API documentation:

- **List Models:** `GET /v1/models`
- **Get Model:** `GET /v1/models/{model}`
- **Chat Completions:** `POST /v1/chat/completions`
- **Embeddings:** `POST /v1/embeddings` (if supported by model)

See OpenAI API documentation for full request/response schemas:
https://platform.openai.com/docs/api-reference

## Examples by Use Case

### Testing Chat Quality
```bash
./testing/06-maas/send-message.sh -m "Write a haiku about kubernetes" --api-key "$API_KEY"
```

### Performance Testing
```bash
# Send multiple requests
for i in {1..10}; do
  time ./testing/06-maas/send-message.sh -m "Count to $i" --api-key "$API_KEY"
done
```

## Related Documentation

- [OpenShift AI MaaS Documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_ai/)
- [KServe LLMInferenceService](https://kserve.github.io/website/docs/model-serving/generative-inference/)
- [OpenAI API Reference](https://platform.openai.com/docs/api-reference)
