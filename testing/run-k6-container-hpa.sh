#!/bin/bash
# Run k6 HPA test using container (podman/docker) with mounted scripts
# No local k6 installation required

set -e

MODEL="${MODEL:-distilbert}"
NAMESPACE="${NAMESPACE:-model-distilbert}"
CONTAINER_ENGINE="${CONTAINER_ENGINE:-podman}"

echo "=========================================="
echo "k6 HPA Test (Containerized)"
echo "=========================================="
echo "Model: ${MODEL}"
echo "Namespace: ${NAMESPACE}"
echo "Container Engine: ${CONTAINER_ENGINE}"
echo "=========================================="

# Check container engine
if ! command -v ${CONTAINER_ENGINE} &> /dev/null; then
    echo "Error: ${CONTAINER_ENGINE} not found"
    echo "Install podman or docker, or use OpenShift Job instead:"
    echo "  ./run-k6-job-hpa.sh"
    exit 1
fi

# Get route and token
echo -e "\n[1/3] Getting route and token..."
ROUTE_URL=$(oc get route ${MODEL} -n ${NAMESPACE} -o jsonpath='{.spec.host}')
TOKEN=$(oc whoami -t)

if [ -z "$ROUTE_URL" ]; then
    echo "Error: Route not found for ${MODEL} in ${NAMESPACE}"
    exit 1
fi

echo "Route: https://${ROUTE_URL}"
echo "Token: ${TOKEN:0:20}..."

# Show initial state
echo -e "\n[2/3] Initial HPA state:"
oc get hpa,pods -n ${NAMESPACE} -l serving.kserve.io/inferenceservice=${MODEL}

# Run k6 in container
echo -e "\n[3/3] Running k6 test in container..."
echo "Monitor HPA: watch -n 2 'oc get hpa,pods -n ${NAMESPACE}'"
echo ""

# Get script directory to find k6-scripts
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

${CONTAINER_ENGINE} run --rm \
  -v ${SCRIPT_DIR}/k6-scripts:/scripts:ro,z \
  -e MODEL="${MODEL}" \
  -e ROUTE_URL="${ROUTE_URL}" \
  -e TOKEN="${TOKEN}" \
  docker.io/grafana/k6:latest \
  run /scripts/hpa-test.js

echo ""
echo "=========================================="
echo "Test completed!"
echo "=========================================="

# Show final state
echo -e "\nFinal HPA state:"
oc get hpa,pods -n ${NAMESPACE} -l serving.kserve.io/inferenceservice=${MODEL}

echo ""
echo "HPA will scale down after ~5min of low CPU"
