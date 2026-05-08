#!/bin/bash
# Run k6 load test in container (podman/docker)
# Auto-detects HPA or KEDA scaling mode

set -e

MODEL="${MODEL:-distilbert}"
NAMESPACE="${NAMESPACE:-model-${MODEL}}"
CONTAINER_ENGINE="${CONTAINER_ENGINE:-podman}"

# Get route and token
ROUTE_URL=$(oc get route ${MODEL} -n ${NAMESPACE} -o jsonpath='{.spec.host}' 2>/dev/null)
TOKEN=$(oc whoami -t 2>/dev/null)

if [ -z "$ROUTE_URL" ]; then
    echo "Error: Route not found for ${MODEL} in ${NAMESPACE}"
    exit 1
fi

# Detect scaling mode
if oc get scaledobject -n ${NAMESPACE} ${MODEL}-predictor &>/dev/null; then
    SCALING_MODE="keda"
else
    SCALING_MODE="hpa"
fi

echo "Running k6 load test: ${MODEL} (${SCALING_MODE} mode)"
echo "Monitor: watch -n 2 'oc get hpa,scaledobject,pods -n ${NAMESPACE}'"
echo ""

# Run k6 in container
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

${CONTAINER_ENGINE} run --rm \
  -v ${SCRIPT_DIR}/k6-scripts:/scripts:ro,z \
  -e MODEL="${MODEL}" \
  -e ROUTE_URL="${ROUTE_URL}" \
  -e TOKEN="${TOKEN}" \
  -e SCALING_MODE="${SCALING_MODE}" \
  docker.io/grafana/k6:latest \
  run /scripts/load-test.js
