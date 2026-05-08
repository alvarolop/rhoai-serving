#!/bin/bash
# Run k6 HPA test as OpenShift Job
# Uses ConfigMap for scripts and Secret for token

set -e

MODEL="${MODEL:-distilbert}"
NAMESPACE="${NAMESPACE:-model-distilbert}"
TEST_NAMESPACE="${TEST_NAMESPACE:-${NAMESPACE}}"

echo "=========================================="
echo "k6 HPA Test (OpenShift Job)"
echo "=========================================="
echo "Model: ${MODEL}"
echo "Model Namespace: ${NAMESPACE}"
echo "Test Namespace: ${TEST_NAMESPACE}"
echo "=========================================="

# Get route and token
echo -e "\n[1/5] Getting route and token..."
ROUTE_URL=$(oc get route ${MODEL} -n ${NAMESPACE} -o jsonpath='{.spec.host}')
TOKEN=$(oc whoami -t)

if [ -z "$ROUTE_URL" ]; then
    echo "Error: Route not found for ${MODEL} in ${NAMESPACE}"
    exit 1
fi

echo "Route: https://${ROUTE_URL}"

# Create test namespace if needed
echo -e "\n[2/5] Ensuring test namespace exists..."
oc get namespace ${TEST_NAMESPACE} >/dev/null 2>&1 || \
  oc create namespace ${TEST_NAMESPACE}

# Create ConfigMap with k6 scripts
echo -e "\n[3/5] Creating ConfigMap with k6 scripts..."
oc apply -f manifests/configmap-k6-scripts.yaml -n ${TEST_NAMESPACE}

# Create Secret with token
echo -e "\n[4/5] Creating Secret with auth token..."
oc create secret generic k6-test-token \
  --from-literal=token="${TOKEN}" \
  -n ${TEST_NAMESPACE} \
  --dry-run=client -o yaml | oc apply -f -

# Create and run Job
echo -e "\n[5/5] Creating k6 Job..."

# Delete previous job if exists
oc delete job k6-hpa-test -n ${TEST_NAMESPACE} --ignore-not-found=true

# Apply job with environment variable overrides
cat manifests/job-k6-hpa.yaml | \
  sed "s|value: \"distilbert\"|value: \"${MODEL}\"|" | \
  sed "s|value: \"\"|value: \"${ROUTE_URL}\"|" | \
  oc apply -f - -n ${TEST_NAMESPACE}

echo ""
echo "Job created! Monitor with:"
echo "  oc logs -f job/k6-hpa-test -n ${TEST_NAMESPACE}"
echo ""
echo "Watch HPA scaling:"
echo "  watch -n 2 'oc get hpa,pods -n ${NAMESPACE}'"
echo ""
echo "Job status:"
echo "  oc get job k6-hpa-test -n ${TEST_NAMESPACE}"

# Wait for job to start
sleep 2

# Follow logs
echo ""
echo "=========================================="
echo "Following Job logs..."
echo "=========================================="
oc logs -f job/k6-hpa-test -n ${TEST_NAMESPACE} 2>/dev/null || \
  echo "Job not started yet. Check logs with: oc logs -f job/k6-hpa-test -n ${TEST_NAMESPACE}"

echo ""
echo "=========================================="
echo "Test completed!"
echo "=========================================="

# Show final state
echo -e "\nJob status:"
oc get job k6-hpa-test -n ${TEST_NAMESPACE}

echo -e "\nFinal HPA state:"
oc get hpa,pods -n ${NAMESPACE} -l serving.kserve.io/inferenceservice=${MODEL}

echo ""
echo "=========================================="
echo "Cleanup:"
echo "  oc delete job k6-hpa-test -n ${TEST_NAMESPACE}"
echo "=========================================="
