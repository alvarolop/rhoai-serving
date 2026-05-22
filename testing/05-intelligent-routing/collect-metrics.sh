#!/bin/bash
set -e

# Usage (from repo root):
#   ./testing/05-intelligent-routing/collect-metrics.sh [DEPLOYMENT_NAME] [NAMESPACE]
#   ./testing/05-intelligent-routing/collect-metrics.sh gpt-oss-20b model-gpt-oss

DEPLOYMENT_NAME="${1:-gpt-oss-20b}"
NAMESPACE="${2:-model-gpt-oss}"

echo "========================================="
echo "Collecting Metrics from vLLM Pods"
echo "Deployment: ${DEPLOYMENT_NAME}"
echo "Namespace: ${NAMESPACE}"
echo "========================================="
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

# Collect metrics from each pod
for i in "${!PODS[@]}"; do
  pod="${PODS[$i]}"
  echo "========================================="
  echo "Pod $((i+1))/${#PODS[@]}: ${pod}"
  echo "========================================="
  echo ""

  # Check if pod is ready
  STATUS=$(oc get pod "${pod}" -n "${NAMESPACE}" -o jsonpath='{.status.phase}')
  if [ "${STATUS}" != "Running" ]; then
    echo "⚠️  Warning: Pod is in ${STATUS} state, skipping..."
    echo ""
    continue
  fi

  # Get full metrics
  echo "📊 Full vLLM Metrics:"
  echo "---"
  oc exec -n "${NAMESPACE}" "${pod}" -c kserve-container -- \
    curl -s http://localhost:8000/metrics 2>/dev/null || echo "❌ Failed to retrieve metrics"
  echo ""
  echo ""

  # Extract key metrics
  echo "🎯 Key Metrics:"
  echo "---"
  METRICS=$(oc exec -n "${NAMESPACE}" "${pod}" -c kserve-container -- \
    curl -s http://localhost:8000/metrics 2>/dev/null || echo "")

  # Cache-related metrics
  echo "Cache Metrics:"
  echo "${METRICS}" | grep -E 'cache' | grep -v "^#" || echo "  (no cache metrics found)"
  echo ""

  # Prefix caching metrics
  echo "Prefix Caching:"
  echo "${METRICS}" | grep -E 'prefix' | grep -v "^#" || echo "  (no prefix metrics found)"
  echo ""

  # Queue metrics
  echo "Queue Depth:"
  echo "${METRICS}" | grep -E 'num_requests_waiting|num_requests_running' | grep -v "^#" || echo "  (no queue metrics found)"
  echo ""

  # KV cache utilization
  echo "KV Cache Utilization:"
  echo "${METRICS}" | grep -E 'kv_cache_usage' | grep -v "^#" || echo "  (no KV cache metrics found)"
  echo ""

  echo ""
done

echo "========================================="
echo "Metrics Collection Complete"
echo "========================================="
echo ""
echo "💡 To monitor metrics in real-time:"
echo "   watch -n 2 './testing/05-intelligent-routing/collect-metrics.sh ${DEPLOYMENT_NAME} ${NAMESPACE}'"
echo ""
echo "💡 To check EPP scheduler logs:"
echo "   oc logs -n ${NAMESPACE} deployment/${DEPLOYMENT_NAME}-epp --tail=50"
echo ""
echo "💡 To verify InferencePool:"
echo "   oc get InferencePool -n ${NAMESPACE}"
