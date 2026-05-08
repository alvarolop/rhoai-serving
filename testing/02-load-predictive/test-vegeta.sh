#!/bin/bash
# Vegeta-based load test for predictive model autoscaling
# Simple alternative to k6 for quick benchmarks

set -e

MODEL="${MODEL:-distilbert}"
NAMESPACE="${NAMESPACE:-model-distilbert}"
DURATION="${DURATION:-180s}"
RATE="${RATE:-50/1s}"

echo "=========================================="
echo "Vegeta Load Test"
echo "=========================================="
echo "Model: ${MODEL}"
echo "Namespace: ${NAMESPACE}"
echo "Duration: ${DURATION}"
echo "Rate: ${RATE}"
echo "=========================================="

# Check if vegeta is installed
if ! command -v vegeta &> /dev/null; then
    echo "Error: vegeta not found. Install with:"
    echo "  sudo dnf install -y vegeta"
    echo ""
    echo "Or use k6 instead: ./test-k6-hpa.sh"
    exit 1
fi

# Get route URL and token
ROUTE_URL=$(oc get route ${MODEL} -n ${NAMESPACE} -o jsonpath='{.spec.host}')
TOKEN=$(oc whoami -t)

echo "Target URL: https://${ROUTE_URL}"
echo ""

# Create vegeta target file
cat > /tmp/vegeta-targets.txt <<EOF
POST https://${ROUTE_URL}/v2/models/${MODEL}/infer
Authorization: Bearer ${TOKEN}
Content-Type: application/json

{"inputs": "Load testing sentence for autoscaling demonstration."}
EOF

echo "Initial state:"
oc get hpa,pods -n ${NAMESPACE} -l serving.kserve.io/inferenceservice=${MODEL}

echo -e "\n=========================================="
echo "Starting load test..."
echo "Monitor with: watch -n 2 'oc get hpa,pods -n ${NAMESPACE}'"
echo "=========================================="
echo ""

# Run vegeta attack
vegeta attack \
    -targets=/tmp/vegeta-targets.txt \
    -duration=${DURATION} \
    -rate=${RATE} \
    -insecure \
    | tee /tmp/vegeta-results.bin \
    | vegeta report -type=text

echo -e "\n=========================================="
echo "Load test completed"
echo "=========================================="

echo -e "\nFinal state:"
oc get hpa,pods -n ${NAMESPACE} -l serving.kserve.io/inferenceservice=${MODEL}

echo -e "\nDetailed metrics:"
cat /tmp/vegeta-results.bin | vegeta report -type=text

# Generate HTML plot
cat /tmp/vegeta-results.bin | vegeta plot > /tmp/vegeta-plot-${MODEL}.html
echo -e "\nHTML plot saved to: /tmp/vegeta-plot-${MODEL}.html"
echo "Open with: firefox /tmp/vegeta-plot-${MODEL}.html"

# Cleanup
rm -f /tmp/vegeta-targets.txt /tmp/vegeta-results.bin

echo -e "\n=========================================="
echo "HPA will scale down after ~5min of low CPU"
echo "To run with higher load:"
echo "  RATE=100/1s DURATION=300s ./test-vegeta.sh"
echo "=========================================="
