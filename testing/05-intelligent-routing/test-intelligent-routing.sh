#!/bin/bash
set -e

# Usage (from repo root):
#   ./testing/05-intelligent-routing/test-intelligent-routing.sh [DEPLOYMENT_NAME] [NAMESPACE] [MODEL_NAME]
#   ./testing/05-intelligent-routing/test-intelligent-routing.sh gpt-oss-20b model-gpt-oss gpt-oss-20b

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
echo "Testing Intelligent Routing"
echo "Deployment: ${DEPLOYMENT_NAME}"
echo "OpenAI model: ${MODEL_NAME}"
echo "Namespace: ${NAMESPACE}"
echo "========================================="
echo ""

# Get model route
echo "📡 Getting model route..."
MODEL_ROUTE=$(oc get route "${DEPLOYMENT_NAME}" -n "${NAMESPACE}" -o jsonpath='{.spec.host}' 2>/dev/null)
if [ -z "$MODEL_ROUTE" ]; then
  echo "❌ ERROR: Route ${DEPLOYMENT_NAME} not found in namespace ${NAMESPACE}"
  exit 1
fi
MODEL_URL="https://${MODEL_ROUTE}"
echo "✅ Model URL: ${MODEL_URL}"
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

# Get vLLM pods
echo "🔍 Finding vLLM pods..."
PODS=($(oc get pods -n "${NAMESPACE}" -l serving.kserve.io/llminferenceservice="${DEPLOYMENT_NAME}" -o jsonpath='{.items[*].metadata.name}'))
if [ ${#PODS[@]} -eq 0 ]; then
  echo "❌ ERROR: No pods found for LLMInferenceService ${DEPLOYMENT_NAME}"
  exit 1
fi
echo "✅ Found ${#PODS[@]} pod(s): ${PODS[*]}"
echo ""

# Function to get metrics from a pod
get_pod_metrics() {
  local pod=$1
  local namespace=$2

  # Get metrics from vLLM /metrics endpoint
  oc exec -n "${namespace}" "${pod}" -c kserve-container -- curl -s http://localhost:8000/metrics 2>/dev/null || echo ""
}

# Function to extract cache hit rate from metrics
extract_cache_hits() {
  local metrics=$1

  # vLLM exposes cache hits via prefix caching metrics
  # Look for vllm:prefix_cache_hit_rate or similar
  echo "${metrics}" | grep -E "vllm.*cache.*hit" | head -1 || echo "N/A"
}

# Collect initial metrics
echo "📊 Collecting initial metrics from pods..."
declare -A INITIAL_METRICS
for pod in "${PODS[@]}"; do
  echo "  - ${pod}"
  INITIAL_METRICS[$pod]=$(get_pod_metrics "${pod}" "${NAMESPACE}")
done
echo ""

# Test requests with shared prefixes
echo "========================================="
echo "Sending Test Requests with Shared Prefixes"
echo "========================================="
echo ""

# Request set 1: Paris-related (shared prefix)
echo "📝 Request 1a: Tell me about Paris"
START1A=$(date +%s%3N)
RESPONSE1A=$(curl -k -s -X POST "${MODEL_URL}/v1/chat/completions" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "'"${MODEL_NAME}"'",
    "messages": [
      {"role": "user", "content": "Tell me about Paris"}
    ],
    "max_tokens": 50
  }')
END1A=$(date +%s%3N)
TTFT1A=$((END1A - START1A))
echo "  ⏱️  TTFT: ${TTFT1A}ms"
echo ""

sleep 1

echo "📝 Request 1b: Tell me about Paris and its history (shared prefix with 1a)"
START1B=$(date +%s%3N)
RESPONSE1B=$(curl -k -s -X POST "${MODEL_URL}/v1/chat/completions" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "'"${MODEL_NAME}"'",
    "messages": [
      {"role": "user", "content": "Tell me about Paris and its history"}
    ],
    "max_tokens": 50
  }')
END1B=$(date +%s%3N)
TTFT1B=$((END1B - START1B))
echo "  ⏱️  TTFT: ${TTFT1B}ms"
echo ""

sleep 1

# Request set 2: London-related (shared prefix)
echo "📝 Request 2a: Tell me about London"
START2A=$(date +%s%3N)
RESPONSE2A=$(curl -k -s -X POST "${MODEL_URL}/v1/chat/completions" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "'"${MODEL_NAME}"'",
    "messages": [
      {"role": "user", "content": "Tell me about London"}
    ],
    "max_tokens": 50
  }')
END2A=$(date +%s%3N)
TTFT2A=$((END2A - START2A))
echo "  ⏱️  TTFT: ${TTFT2A}ms"
echo ""

sleep 1

echo "📝 Request 2b: Tell me about London and its culture (shared prefix with 2a)"
START2B=$(date +%s%3N)
RESPONSE2B=$(curl -k -s -X POST "${MODEL_URL}/v1/chat/completions" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "'"${MODEL_NAME}"'",
    "messages": [
      {"role": "user", "content": "Tell me about London and its culture"}
    ],
    "max_tokens": 50
  }')
END2B=$(date +%s%3N)
TTFT2B=$((END2B - START2B))
echo "  ⏱️  TTFT: ${TTFT2B}ms"
echo ""

# Collect final metrics
echo "📊 Collecting final metrics from pods..."
declare -A FINAL_METRICS
for pod in "${PODS[@]}"; do
  echo "  - ${pod}"
  FINAL_METRICS[$pod]=$(get_pod_metrics "${pod}" "${NAMESPACE}")
done
echo ""

# Analyze results
echo "========================================="
echo "Results Analysis"
echo "========================================="
echo ""

echo "📈 TTFT Comparison:"
echo "  Request 1a (Paris):              ${TTFT1A}ms"
echo "  Request 1b (Paris + history):    ${TTFT1B}ms ($(((TTFT1A - TTFT1B) * 100 / TTFT1A))% ${TTFT1B} < ${TTFT1A} && echo 'faster ✓' || echo 'slower')"
echo "  Request 2a (London):             ${TTFT2A}ms"
echo "  Request 2b (London + culture):   ${TTFT2B}ms ($(((TTFT2A - TTFT2B) * 100 / TTFT2A))% ${TTFT2B} < ${TTFT2A} && echo 'faster ✓' || echo 'slower')"
echo ""

echo "📊 Cache Metrics Per Pod:"
for pod in "${PODS[@]}"; do
  echo ""
  echo "Pod: ${pod}"
  echo "  Initial cache stats:"
  extract_cache_hits "${INITIAL_METRICS[$pod]}" | sed 's/^/    /'
  echo "  Final cache stats:"
  extract_cache_hits "${FINAL_METRICS[$pod]}" | sed 's/^/    /'
done
echo ""

# Expected behavior analysis
echo "========================================="
echo "Expected Behavior with Intelligent Routing:"
echo "========================================="
echo "✓ Requests with shared prefixes should land on the SAME pod"
echo "✓ Second request in each pair should have LOWER TTFT (cache hit)"
echo "✓ Cache hit rate should be ~50% (2 out of 4 requests reuse cache)"
echo ""
echo "Without intelligent routing (round-robin):"
echo "✗ Requests distributed randomly across pods"
echo "✗ No TTFT improvement on shared prefix requests"
echo "✗ Cache hit rate near 0%"
echo ""

echo "========================================="
echo "Detailed Metrics Collection"
echo "========================================="
echo "To verify intelligent routing, check vLLM metrics on each pod:"
echo ""
for pod in "${PODS[@]}"; do
  echo "oc exec -n ${NAMESPACE} ${pod} -c kserve-container -- curl -s http://localhost:8000/metrics | grep -E 'cache|prefix'"
done
echo ""

echo "========================================="
echo "Test Complete"
echo "========================================="
