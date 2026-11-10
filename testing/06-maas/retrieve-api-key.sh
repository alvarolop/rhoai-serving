#!/bin/bash
# Retrieve or create API key for a MaaS subscription
#
# This script follows the official MaaS validation pattern:
# https://opendatahub-io.github.io/models-as-a-service/0.0.1/install/validation/
#
# Usage:
#   ./retrieve-api-key.sh [OPTIONS]
#
# Options:
#   --subscription, -s NAME  MaaS subscription name (default: basic-models)
#
# Examples:
#   # Use default subscription (basic-models)
#   ./retrieve-api-key.sh
#
#   # Use specific subscription
#   ./retrieve-api-key.sh --subscription my-subscription
#   ./retrieve-api-key.sh -s my-subscription

set -euo pipefail

# Parse arguments
MAAS_SUBSCRIPTION_NAME="basic-models"

while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--subscription)
            MAAS_SUBSCRIPTION_NAME="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--subscription NAME]"
            exit 1
            ;;
    esac
done

# Auto-detect MaaS URL from cluster or use explicit override
if [ -z "${MAAS_URL:-}" ]; then
    # Get cluster domain from OpenShift ingress config
    CLUSTER_DOMAIN=$(oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}' 2>/dev/null || echo "")

    if [ -z "$CLUSTER_DOMAIN" ]; then
        echo "Error: Could not auto-detect cluster domain"
        echo "Please set MAAS_URL environment variable:"
        echo "  MAAS_URL=https://maas.example.com $0 $*"
        exit 1
    fi

    # Try maas subdomain first
    MAAS_URL="https://maas.${CLUSTER_DOMAIN}"
    echo "==> Auto-detected MaaS URL: ${MAAS_URL}"

    # Check if maas gateway exists, fallback to gateway
    if ! curl -sSk -f "${MAAS_URL}/maas-api/v1/subscriptions" \
        -H "Authorization: Bearer $(oc whoami -t)" \
        &> /dev/null; then
        MAAS_URL="https://gateway.${CLUSTER_DOMAIN}"
        echo "==> Using fallback gateway URL: ${MAAS_URL}"
    fi
fi

# Get OpenShift token for authentication
OC_TOKEN=$(oc whoami -t 2>/dev/null || echo "")
if [ -z "$OC_TOKEN" ]; then
    echo "Error: Could not get OpenShift token"
    echo "Make sure you are logged in: oc login"
    exit 1
fi

echo "==> Authenticated as: $(oc whoami)"
echo ""

# Prepare API key creation request
API_KEY_NAME="cli-key-$(date +%s)"
EXPIRES_IN="720h"  # 1 month (30 days)

# Build JSON payload
JSON_PAYLOAD=$(cat <<EOF
{
  "name": "${API_KEY_NAME}",
  "description": "Created by retrieve-api-key.sh",
  "expiresIn": "${EXPIRES_IN}",
  "subscription": "${MAAS_SUBSCRIPTION_NAME}"
}
EOF
)
echo "==> Creating API key for subscription: ${MAAS_SUBSCRIPTION_NAME}"

# Create API key
API_KEY_RESPONSE=$(curl -sSk \
    -H "Authorization: Bearer ${OC_TOKEN}" \
    -H "Content-Type: application/json" \
    -X POST \
    -d "${JSON_PAYLOAD}" \
    "${MAAS_URL}/maas-api/v1/api-keys" 2>/dev/null)

# Extract API key from response
API_KEY=$(echo "$API_KEY_RESPONSE" | jq -r '.key // empty' 2>/dev/null)

if [ -z "$API_KEY" ]; then
    echo "Error: Failed to create API key"
    echo ""
    echo "Response from server:"
    echo "$API_KEY_RESPONSE" | jq '.' 2>/dev/null || echo "$API_KEY_RESPONSE"
    exit 1
fi

echo "==> API Key created successfully"
echo "==> Key name: ${API_KEY_NAME}"
echo "==> Expires in: ${EXPIRES_IN}"
echo ""
echo "# Export to environment:"
echo "export MAAS_API_KEY='${API_KEY}'"
echo "export MAAS_URL='${MAAS_URL}'"
echo ""
echo "# Or use directly:"
echo "curl -H \"Authorization: Bearer ${API_KEY}\" ${MAAS_URL}/v1/models"
echo ""
echo "Note: API key is shown only once. Store it securely."
