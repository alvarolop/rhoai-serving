#!/bin/bash
# Functional test for DistilBERT predictive model
# Validates that the model responds correctly to inference requests

set -e

MODEL="${MODEL:-distilbert}"
NAMESPACE="${NAMESPACE:-model-distilbert}"
PAYLOAD="${PAYLOAD:-{\"inputs\": \"This is a test sentence for classification.\"}}"

echo "=========================================="
echo "Functional Test: ${MODEL}"
echo "=========================================="
echo "Namespace: ${NAMESPACE}"
echo "Payload: ${PAYLOAD}"
echo "=========================================="

# Get route URL
echo -e "\n[1/4] Getting route URL..."
ROUTE_URL=$(oc get route ${MODEL} -n ${NAMESPACE} -o jsonpath='{.spec.host}' 2>/dev/null)
if [ -z "$ROUTE_URL" ]; then
    echo "Error: Route not found for model '${MODEL}' in namespace '${NAMESPACE}'"
    echo "Is the model deployed?"
    exit 1
fi
echo "Route: https://${ROUTE_URL}"

# Get authentication token
echo -e "\n[2/4] Getting authentication token..."
TOKEN=$(oc whoami -t)
echo "Token: ${TOKEN:0:20}..."

# Check model readiness
echo -e "\n[3/4] Checking model health..."
HEALTH_RESPONSE=$(curl -sk -w "\nHTTP_CODE:%{http_code}" \
    "https://${ROUTE_URL}/v2/health/ready" \
    -H "Authorization: Bearer ${TOKEN}")

HTTP_CODE=$(echo "$HEALTH_RESPONSE" | grep "HTTP_CODE:" | cut -d: -f2)
if [ "$HTTP_CODE" != "200" ]; then
    echo "Error: Model not ready (HTTP ${HTTP_CODE})"
    echo "$HEALTH_RESPONSE"
    exit 1
fi
echo "✓ Model is ready"

# Send inference request
echo -e "\n[4/4] Sending inference request..."
echo "Request: POST https://${ROUTE_URL}/v2/models/${MODEL}/infer"
echo "Payload: ${PAYLOAD}"
echo ""

START_TIME=$(date +%s%N)
RESPONSE=$(curl -sk -w "\nHTTP_CODE:%{http_code}\nTIME_TOTAL:%{time_total}" \
    -X POST "https://${ROUTE_URL}/v2/models/${MODEL}/infer" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d "${PAYLOAD}")

END_TIME=$(date +%s%N)
HTTP_CODE=$(echo "$RESPONSE" | grep "HTTP_CODE:" | cut -d: -f2)
TIME_TOTAL=$(echo "$RESPONSE" | grep "TIME_TOTAL:" | cut -d: -f2)
BODY=$(echo "$RESPONSE" | sed '/HTTP_CODE:/d' | sed '/TIME_TOTAL:/d')

echo "=========================================="
echo "Response:"
echo "=========================================="

if [ "$HTTP_CODE" = "200" ]; then
    echo "✓ HTTP Status: 200 OK"
    echo "✓ Response Time: ${TIME_TOTAL}s"
    echo ""
    echo "Response Body:"
    echo "$BODY" | jq . 2>/dev/null || echo "$BODY"
    echo ""

    # Validate response structure
    echo "Validation:"
    if echo "$BODY" | jq -e '.outputs' > /dev/null 2>&1 || \
       echo "$BODY" | jq -e '.predictions' > /dev/null 2>&1; then
        echo "✓ Response contains outputs/predictions"
    else
        echo "⚠ Warning: Response does not contain expected 'outputs' or 'predictions' field"
    fi

    # Extract and display key information
    if echo "$BODY" | jq -e '.model_name' > /dev/null 2>&1; then
        MODEL_NAME=$(echo "$BODY" | jq -r '.model_name')
        echo "✓ Model name: ${MODEL_NAME}"
    fi

    echo ""
    echo "=========================================="
    echo "✓ Functional test PASSED"
    echo "=========================================="
    exit 0
else
    echo "✗ HTTP Status: ${HTTP_CODE}"
    echo ""
    echo "Error Response:"
    echo "$BODY"
    echo ""
    echo "=========================================="
    echo "✗ Functional test FAILED"
    echo "=========================================="
    exit 1
fi
