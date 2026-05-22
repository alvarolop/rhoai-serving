#!/bin/bash
set -e

# Usage (from repo root):
#   ./testing/05-intelligent-routing/verify-routing-config.sh [DEPLOYMENT_NAME] [NAMESPACE]
#   ./testing/05-intelligent-routing/verify-routing-config.sh gpt-oss-20b model-gpt-oss

DEPLOYMENT_NAME="${1:-gpt-oss-20b}"
NAMESPACE="${2:-model-gpt-oss}"

echo "========================================="
echo "Verifying Intelligent Routing Configuration"
echo "Deployment: ${DEPLOYMENT_NAME}"
echo "Namespace: ${NAMESPACE}"
echo "========================================="
echo ""

# Check 1: LLMInferenceService exists
echo "1️⃣  Checking LLMInferenceService..."
if ! oc get LLMInferenceService "${DEPLOYMENT_NAME}" -n "${NAMESPACE}" &>/dev/null; then
  echo "❌ LLMInferenceService '${DEPLOYMENT_NAME}' not found in namespace '${NAMESPACE}'"
  exit 1
fi
echo "✅ LLMInferenceService exists"
echo ""

# Check 2: Router configuration
echo "2️⃣  Checking router configuration..."
ROUTER_CONFIG=$(oc get LLMInferenceService "${DEPLOYMENT_NAME}" -n "${NAMESPACE}" -o yaml | grep -A 10 "router:")
echo "${ROUTER_CONFIG}"
echo ""

if echo "${ROUTER_CONFIG}" | grep -q "scheduler: {}"; then
  echo "✅ Intelligent routing ENABLED (scheduler section present)"
  ROUTING_ENABLED=true
else
  echo "❌ Intelligent routing DISABLED (no scheduler section)"
  ROUTING_ENABLED=false
fi
echo ""

# Check 3: InferencePool (only if intelligent routing is enabled)
if [ "${ROUTING_ENABLED}" = true ]; then
  echo "3️⃣  Checking InferencePool..."
  if oc get InferencePool "${DEPLOYMENT_NAME}" -n "${NAMESPACE}" &>/dev/null; then
    echo "✅ InferencePool '${DEPLOYMENT_NAME}' exists"
    echo ""
    echo "InferencePool details:"
    oc get InferencePool "${DEPLOYMENT_NAME}" -n "${NAMESPACE}" -o yaml | grep -A 15 "spec:"
  else
    echo "⚠️  InferencePool '${DEPLOYMENT_NAME}' not found (may still be creating)"
  fi
  echo ""
else
  echo "3️⃣  Skipping InferencePool check (intelligent routing disabled)"
  echo ""
fi

# Check 4: EPP deployment (only if intelligent routing is enabled)
if [ "${ROUTING_ENABLED}" = true ]; then
  echo "4️⃣  Checking EPP (Endpoint Picker) deployment..."
  EPP_NAME="${DEPLOYMENT_NAME}-epp"
  if oc get deployment "${EPP_NAME}" -n "${NAMESPACE}" &>/dev/null; then
    EPP_STATUS=$(oc get deployment "${EPP_NAME}" -n "${NAMESPACE}" -o jsonpath='{.status.conditions[?(@.type=="Available")].status}')
    EPP_REPLICAS=$(oc get deployment "${EPP_NAME}" -n "${NAMESPACE}" -o jsonpath='{.status.availableReplicas}')

    if [ "${EPP_STATUS}" = "True" ]; then
      echo "✅ EPP deployment '${EPP_NAME}' is available (${EPP_REPLICAS} replica(s))"
    else
      echo "⚠️  EPP deployment '${EPP_NAME}' exists but not available yet"
    fi
  else
    echo "⚠️  EPP deployment '${EPP_NAME}' not found (may still be creating)"
  fi
  echo ""
else
  echo "4️⃣  Skipping EPP check (intelligent routing disabled)"
  echo ""
fi

# Check 5: Model replicas
echo "5️⃣  Checking model replicas..."
PODS=($(oc get pods -n "${NAMESPACE}" -l serving.kserve.io/llminferenceservice="${DEPLOYMENT_NAME}" -o jsonpath='{.items[*].metadata.name}'))
if [ ${#PODS[@]} -eq 0 ]; then
  echo "❌ No vLLM pods found"
  exit 1
elif [ ${#PODS[@]} -eq 1 ]; then
  echo "⚠️  Only 1 replica found - intelligent routing requires 2+ replicas for meaningful results"
  echo "   Pod: ${PODS[0]}"
else
  echo "✅ Found ${#PODS[@]} replica(s):"
  for pod in "${PODS[@]}"; do
    STATUS=$(oc get pod "${pod}" -n "${NAMESPACE}" -o jsonpath='{.status.phase}')
    echo "   - ${pod} (${STATUS})"
  done
fi
echo ""

# Summary
echo "========================================="
echo "Summary"
echo "========================================="
echo ""
if [ "${ROUTING_ENABLED}" = true ]; then
  echo "🎯 Intelligent Routing: ENABLED"
  echo ""
  echo "Expected behavior:"
  echo "  ✓ Requests with shared prefixes route to same pod"
  echo "  ✓ KV cache reuse improves TTFT on subsequent requests"
  echo "  ✓ EPP scheduler balances load based on queue depth and cache state"
  echo ""
  if [ ${#PODS[@]} -lt 2 ]; then
    echo "⚠️  WARNING: Only ${#PODS[@]} replica(s) - scale to 2+ for better routing visibility"
    echo "   kubectl scale LLMInferenceService/${DEPLOYMENT_NAME} --replicas=2 -n ${NAMESPACE}"
  fi
else
  echo "🔄 Intelligent Routing: DISABLED"
  echo ""
  echo "Expected behavior:"
  echo "  → Round-robin load balancing"
  echo "  → No cache-aware routing"
  echo "  → No TTFT improvements on shared prefixes"
  echo ""
  echo "To enable intelligent routing, update your values.yaml:"
  echo "  serving:"
  echo "    router:"
  echo "      intelligentRouting:"
  echo "        enabled: true"
fi
echo ""

echo "========================================="
echo "Next Steps"
echo "========================================="
echo ""
echo "Run the intelligent routing test:"
echo "  ./testing/05-intelligent-routing/test-intelligent-routing.sh ${DEPLOYMENT_NAME} ${NAMESPACE}"
echo ""
echo "Collect detailed metrics:"
echo "  ./testing/05-intelligent-routing/collect-metrics.sh ${DEPLOYMENT_NAME} ${NAMESPACE}"
echo ""
if [ "${ROUTING_ENABLED}" = true ]; then
  echo "Check EPP logs:"
  echo "  oc logs -n ${NAMESPACE} deployment/${DEPLOYMENT_NAME}-epp --tail=50"
  echo ""
fi
