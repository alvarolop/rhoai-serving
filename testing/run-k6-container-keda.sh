#!/bin/bash
# Run k6 KEDA test using container (podman/docker) with mounted scripts

set -e

MODEL="${MODEL:-distilbert}"
NAMESPACE="${NAMESPACE:-model-distilbert}"
CONTAINER_ENGINE="${CONTAINER_ENGINE:-podman}"

echo "=========================================="
echo "k6 KEDA Test (Containerized)"
echo "=========================================="
echo "Model: ${MODEL}"
echo "Namespace: ${NAMESPACE}"
echo "Container Engine: ${CONTAINER_ENGINE}"
echo "=========================================="

if ! command -v ${CONTAINER_ENGINE} &> /dev/null; then
    echo "Error: ${CONTAINER_ENGINE} not found"
    echo "Use OpenShift Job instead: ./run-k6-job-keda.sh"
    exit 1
fi

echo -e "\n[1/3] Getting route and token..."
ROUTE_URL=$(oc get route ${MODEL} -n ${NAMESPACE} -o jsonpath='{.spec.host}')
TOKEN=$(oc whoami -t)

if [ -z "$ROUTE_URL" ]; then
    echo "Error: Route not found for ${MODEL} in ${NAMESPACE}"
    exit 1
fi

echo "Route: https://${ROUTE_URL}"

echo -e "\n[2/3] Initial KEDA state:"
oc get scaledobject,pods -n ${NAMESPACE} 2>/dev/null || \
  echo "No ScaledObject found (deploy with scaling.mode: keda)"

echo -e "\n[3/3] Running k6 test in container..."
echo "Monitor KEDA: watch -n 2 'oc get scaledobject,pods -n ${NAMESPACE}'"
echo ""

${CONTAINER_ENGINE} run --rm \
  -v $(pwd)/k6-scripts:/scripts:ro,z \
  -e MODEL="${MODEL}" \
  -e ROUTE_URL="${ROUTE_URL}" \
  -e TOKEN="${TOKEN}" \
  docker.io/grafana/k6:latest \
  run /scripts/keda-test.js

echo ""
echo "=========================================="
echo "Test completed!"
echo "=========================================="

echo -e "\nFinal KEDA state:"
oc get scaledobject,pods -n ${NAMESPACE} 2>/dev/null || echo "No ScaledObject"

echo ""
echo "KEDA will scale down based on pollingInterval"
