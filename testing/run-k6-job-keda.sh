#!/bin/bash
# Run k6 KEDA test as OpenShift Job

set -e

MODEL="${MODEL:-distilbert}"
NAMESPACE="${NAMESPACE:-model-distilbert}"
TEST_NAMESPACE="${TEST_NAMESPACE:-${NAMESPACE}}"

echo "=========================================="
echo "k6 KEDA Test (OpenShift Job)"
echo "=========================================="
echo "Model: ${MODEL}"
echo "Model Namespace: ${NAMESPACE}"
echo "Test Namespace: ${TEST_NAMESPACE}"
echo "=========================================="

echo -e "\n[1/5] Getting route and token..."
ROUTE_URL=$(oc get route ${MODEL} -n ${NAMESPACE} -o jsonpath='{.spec.host}')
TOKEN=$(oc whoami -t)

if [ -z "$ROUTE_URL" ]; then
    echo "Error: Route not found"
    exit 1
fi

echo "Route: https://${ROUTE_URL}"

echo -e "\n[2/5] Ensuring test namespace exists..."
oc get namespace ${TEST_NAMESPACE} >/dev/null 2>&1 || \
  oc create namespace ${TEST_NAMESPACE}

echo -e "\n[3/5] Creating ConfigMap with k6 scripts..."
oc apply -f manifests/configmap-k6-scripts.yaml -n ${TEST_NAMESPACE}

echo -e "\n[4/5] Creating Secret with auth token..."
oc create secret generic k6-test-token \
  --from-literal=token="${TOKEN}" \
  -n ${TEST_NAMESPACE} \
  --dry-run=client -o yaml | oc apply -f -

echo -e "\n[5/5] Creating k6 Job..."
oc delete job k6-keda-test -n ${TEST_NAMESPACE} --ignore-not-found=true

cat manifests/job-k6-keda.yaml | \
  sed "s|value: \"distilbert\"|value: \"${MODEL}\"|" | \
  sed "s|value: \"\"|value: \"${ROUTE_URL}\"|" | \
  oc apply -f - -n ${TEST_NAMESPACE}

echo ""
echo "Job created! Monitor with:"
echo "  oc logs -f job/k6-keda-test -n ${TEST_NAMESPACE}"
echo ""
echo "Watch KEDA scaling:"
echo "  watch -n 2 'oc get scaledobject,pods -n ${NAMESPACE}'"
echo ""

sleep 2

echo "=========================================="
echo "Following Job logs..."
echo "=========================================="
oc logs -f job/k6-keda-test -n ${TEST_NAMESPACE} 2>/dev/null || \
  echo "Check logs with: oc logs -f job/k6-keda-test -n ${TEST_NAMESPACE}"

echo ""
echo "=========================================="
echo "Test completed!"
echo "=========================================="

echo -e "\nJob status:"
oc get job k6-keda-test -n ${TEST_NAMESPACE}

echo -e "\nFinal KEDA state:"
oc get scaledobject,pods -n ${NAMESPACE} 2>/dev/null || echo "No ScaledObject"

echo ""
echo "Cleanup: oc delete job k6-keda-test -n ${TEST_NAMESPACE}"
