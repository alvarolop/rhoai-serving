#!/bin/bash
set -e

# Usage:
#   ./test-nemo-guardrails.sh [DEPLOYMENT_NAME] [NAMESPACE] [MODEL_NAME]
#   ./test-nemo-guardrails.sh gpt-oss-20b model-gpt-oss RedHatAI/gpt-oss-20b

# Helper function to resolve model name
resolve_api_model_name() {
  local deployment_name=$1
  local namespace=$2
  local override=${3:-}

  if [[ -n "${override}" ]]; then
    echo "${override}"
    return 0
  fi

  local model
  model=$(oc get LLMInferenceService "${deployment_name}" -n "${namespace}" \
    -o jsonpath='{.spec.model.name}' 2>/dev/null || true)
  if [[ -n "${model}" ]]; then
    echo "${model}"
    return 0
  fi

  echo "Warning: could not read spec.model.name for LLMInferenceService '${deployment_name}' in '${namespace}'; using deployment name as model id." >&2
  echo "${deployment_name}"
}

DEPLOYMENT_NAME="${1:-gpt-oss-20b}"
NAMESPACE="${2:-model-gpt-oss}"
MODEL_NAME="$(resolve_api_model_name "${DEPLOYMENT_NAME}" "${NAMESPACE}" "${3:-}")"

echo "========================================="
echo "Testing NeMo Guardrails"
echo "Deployment: ${DEPLOYMENT_NAME}"
echo "OpenAI model: ${MODEL_NAME}"
echo "Namespace: ${NAMESPACE}"
echo "========================================="
echo ""

# Get NeMo Guardrails route
echo "📡 Getting NeMo Guardrails route..."
NEMO_ROUTE=$(oc get route "${DEPLOYMENT_NAME}-nemo-guardrails" -n "${NAMESPACE}" -o jsonpath='{.spec.host}' 2>/dev/null)
if [ -z "$NEMO_ROUTE" ]; then
  echo "❌ ERROR: Route ${DEPLOYMENT_NAME}-nemo-guardrails not found in namespace ${NAMESPACE}"
  exit 1
fi
NEMO_URL="https://${NEMO_ROUTE}"
echo "✅ NeMo URL: ${NEMO_URL}"
echo ""

# Get ServiceAccount token
echo "🔑 Getting authentication token..."
TOKEN=$(oc get secret "${DEPLOYMENT_NAME}-sa-token" -n "${NAMESPACE}" -o jsonpath='{.data.token}' 2>/dev/null | base64 -d)
if [ -z "$TOKEN" ]; then
  echo "❌ ERROR: Secret ${DEPLOYMENT_NAME}-sa-token not found in namespace ${NAMESPACE}"
  exit 1
fi
echo "✅ Token retrieved"
echo ""

# Test 1: Normal request (should work)
echo "========================================="
echo "TEST 1: Normal Request (Should Work)"
echo "========================================="
echo "Sending short message (under 2000 chars)..."
echo ""

RESPONSE=$(curl -k -s -X POST "${NEMO_URL}/v1/chat/completions" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "'"${MODEL_NAME}"'",
    "messages": [
      {"role": "user", "content": "Hello, how are you? Please respond in one sentence."}
    ],
    "max_tokens": 500
  }')

echo "Response:"
echo "${RESPONSE}" | python3 -m json.tool 2>/dev/null || echo "${RESPONSE}"
echo ""

# Test 2: Long message (should trigger guardrail)
echo "========================================="
echo "TEST 2: Long Message (Should Trigger Guardrail)"
echo "========================================="
echo "Sending message with 2001 characters (exceeds 2000 char limit)..."
echo ""

LONG_MESSAGE=$(python3 -c "print('This is a very long message. ' * 100)")

RESPONSE=$(curl -k -s -X POST "${NEMO_URL}/v1/chat/completions" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "'"${MODEL_NAME}"'",
    "messages": [
      {"role": "user", "content": "'"${LONG_MESSAGE}"'"}
    ],
    "max_tokens": 500
  }')

echo "Response:"
echo "${RESPONSE}" | python3 -m json.tool 2>/dev/null || echo "${RESPONSE}"
echo ""

# Check for guardrail message
if echo "${RESPONSE}" | grep -q "too long"; then
  echo "✅ SUCCESS: Guardrail triggered! Message was blocked."
else
  echo "⚠️  WARNING: Guardrail may not have triggered. Check response above."
fi
echo ""

# Test 3: Custom policy - Madrid/Spain topic (should trigger guardrail)
echo "========================================="
echo "TEST 3: Custom Policy - Madrid/Spain Topic (Should Trigger Guardrail)"
echo "========================================="
echo "Sending message about Madrid (custom policy violation)..."
echo ""

RESPONSE=$(curl -k -s -X POST "${NEMO_URL}/v1/chat/completions" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "'"${MODEL_NAME}"'",
    "messages": [
      {"role": "user", "content": "Tell me about the city of Madrid and its attractions."}
    ],
    "max_tokens": 500
  }')

echo "Response:"
echo "${RESPONSE}" | python3 -m json.tool 2>/dev/null || echo "${RESPONSE}"
echo ""

# Check if request was blocked
if echo "${RESPONSE}" | grep -qi "blocked\|cannot\|policy\|not allowed"; then
  echo "✅ SUCCESS: Custom policy triggered! Madrid topic was blocked."
else
  echo "⚠️  WARNING: Custom policy may not have triggered. Check response above."
fi
echo ""

# Test 4: Custom policy - Spain topic (should trigger guardrail)
echo "========================================="
echo "TEST 4: Custom Policy - Spain Topic (Should Trigger Guardrail)"
echo "========================================="
echo "Sending message about Spain (custom policy violation)..."
echo ""

RESPONSE=$(curl -k -s -X POST "${NEMO_URL}/v1/chat/completions" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "'"${MODEL_NAME}"'",
    "messages": [
      {"role": "user", "content": "What is the capital of Spain?"}
    ],
    "max_tokens": 500
  }')

echo "Response:"
echo "${RESPONSE}" | python3 -m json.tool 2>/dev/null || echo "${RESPONSE}"
echo ""

# Check if request was blocked
if echo "${RESPONSE}" | grep -qi "blocked\|cannot\|policy\|not allowed"; then
  echo "✅ SUCCESS: Custom policy triggered! Spain topic was blocked."
else
  echo "⚠️  WARNING: Custom policy may not have triggered. Check response above."
fi
echo ""

echo "========================================="
echo "Test Complete"
echo "========================================="
echo ""
echo "💡 To see guardrails in action, check the logs:"
echo "   oc logs -n ${NAMESPACE} -l app=${DEPLOYMENT_NAME}-nemo-guardrails -c nemo-guardrails --tail=50"
