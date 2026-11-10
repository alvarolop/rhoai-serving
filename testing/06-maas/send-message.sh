#!/bin/bash
# Send a simple message to MaaS API
#
# Usage:
#   ./send-message.sh --message "MESSAGE" [OPTIONS]
#
# Options:
#   --message, -m MESSAGE    Message to send (required)
#   --model MODEL            Model to use (auto-selects if not provided)
#   --api-key KEY            API key (uses MAAS_API_KEY env var if not provided)
#   --max-tokens NUM         Maximum tokens (default: 500)
#
# Examples:
#   # Using environment variable (recommended)
#   export MAAS_API_KEY=sk-abc123
#   ./send-message.sh --message "What is the capital of France?"
#
#   # With specific model
#   ./send-message.sh -m "Hello world" --model mistralai/Devstral-Small-2-24B-Instruct-2512
#
#   # With custom max tokens and API key
#   ./send-message.sh -m "Tell me a story" --max-tokens 1000 --api-key sk-abc123

set -euo pipefail

# Auto-detect MaaS URL from cluster or use explicit override
if [ -z "${MAAS_URL:-}" ]; then
    # Get cluster domain from OpenShift ingress config
    CLUSTER_DOMAIN=$(oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}' 2>/dev/null || echo "")

    if [ -n "$CLUSTER_DOMAIN" ]; then
        MAAS_URL="https://maas.${CLUSTER_DOMAIN}"
    else
        echo "Error: Could not auto-detect cluster domain"
        echo "Please set MAAS_URL environment variable:"
        echo "  MAAS_URL=https://maas.example.com $0 $*"
        exit 1
    fi
fi

# Parse arguments
MESSAGE=""
MODEL=""
API_KEY=""
MAX_TOKENS="${MAX_TOKENS:-500}"

while [[ $# -gt 0 ]]; do
    case $1 in
        -m|--message)
            MESSAGE="$2"
            shift 2
            ;;
        --model)
            MODEL="$2"
            shift 2
            ;;
        --api-key)
            API_KEY="$2"
            shift 2
            ;;
        --max-tokens)
            MAX_TOKENS="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 --message MESSAGE [--model MODEL] [--api-key KEY] [--max-tokens NUM]"
            exit 1
            ;;
    esac
done

# Check required arguments
if [ -z "$MESSAGE" ]; then
    echo "Error: --message is required"
    echo ""
    echo "Usage: $0 --message MESSAGE [OPTIONS]"
    echo ""
    echo "Examples:"
    echo "  $0 --message \"What is the capital of France?\""
    echo "  $0 -m \"Hello\" --model tinyllama-1b --max-tokens 1000"
    exit 1
fi

# Determine API key: 1) --api-key flag, 2) MAAS_API_KEY env var, 3) error
if [ -z "$API_KEY" ]; then
    if [ -n "${MAAS_API_KEY:-}" ]; then
        API_KEY="$MAAS_API_KEY"
        echo "==> Using API key from MAAS_API_KEY environment variable"
    else
        echo "Error: API key not provided"
        echo ""
        echo "Provide API key via:"
        echo "  1. Flag: $0 -m \"message\" --api-key sk-abc123"
        echo "  2. Environment variable: export MAAS_API_KEY=sk-abc123"
        echo ""
        echo "Or create one with:"
        echo "  eval \"\$(./testing/06-maas/retrieve-api-key.sh | grep '^export')\""
        exit 1
    fi
fi

# If no model specified, get the first available model
if [ -z "$MODEL" ]; then
    echo "==> No model specified, fetching first available model..."
    model_response=$(curl -sk -H "Authorization: Bearer ${API_KEY}" "${MAAS_URL}/v1/models")
    MODEL=$(echo "$model_response" | jq -r '.data[0].id' 2>/dev/null || echo "")
    MODEL_URL=$(echo "$model_response" | jq -r '.data[0].url' 2>/dev/null || echo "")

    if [ -z "$MODEL" ]; then
        echo "Error: Could not retrieve available models"
        exit 1
    fi
    echo "==> Using model: ${MODEL}"
else
    # Get model URL for specified model
    MODEL_URL=$(curl -sk -H "Authorization: Bearer ${API_KEY}" \
        "${MAAS_URL}/v1/models" | jq -r ".data[] | select(.id==\"${MODEL}\") | .url" 2>/dev/null || echo "")

    if [ -z "$MODEL_URL" ]; then
        echo "Error: Model '${MODEL}' not found"
        exit 1
    fi
fi

# Send the message
echo "==> Sending to: ${MODEL}"
echo "==> Message: ${MESSAGE}"
echo ""

response=$(curl -sk -w "\n%{http_code}" -X POST \
    -H "Authorization: Bearer ${API_KEY}" \
    -H "Content-Type: application/json" \
    -d "{
        \"model\": \"${MODEL}\",
        \"messages\": [{\"role\": \"user\", \"content\": \"${MESSAGE}\"}],
        \"max_tokens\": ${MAX_TOKENS},
        \"temperature\": 0.7
    }" \
    "${MODEL_URL}/v1/chat/completions")

# Split response body and status code
http_code=$(echo "$response" | tail -n1)
response_body=$(echo "$response" | sed '$d')

# Check for rate limiting
if [ "$http_code" = "429" ]; then
    echo "Error: Rate limit exceeded"
    error_msg=$(echo "$response_body" | jq -r '.error.message // .message // empty' 2>/dev/null)
    if [ -n "$error_msg" ]; then
        echo "$error_msg"
    else
        echo "$response_body" | jq '.' 2>/dev/null || echo "$response_body"
    fi
    exit 1
fi

# Extract and display the response
content=$(echo "$response_body" | jq -r '.choices[0].message.content // empty' 2>/dev/null)

if [ -n "$content" ]; then
    echo "$content"
else
    echo "Error: No response from model (HTTP ${http_code})"
    echo "$response_body" | jq '.' 2>/dev/null || echo "$response_body"
    exit 1
fi
