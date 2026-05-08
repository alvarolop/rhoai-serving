#!/bin/bash
# HPA Scaling Test Script for DistilBERT Model
# This script generates load to test HPA autoscaling behavior

set -e

MODEL_NAME="${MODEL_NAME:-distilbert}"
NAMESPACE="${NAMESPACE:-model-distilbert}"
DURATION="${DURATION:-300}"  # 5 minutes default
CONCURRENT="${CONCURRENT:-10}"
REQUESTS_PER_SECOND="${REQUESTS_PER_SECOND:-5}"

echo "=========================================="
echo "HPA Autoscaling Test for ${MODEL_NAME}"
echo "=========================================="
echo "Namespace: ${NAMESPACE}"
echo "Test Duration: ${DURATION}s"
echo "Concurrent Requests: ${CONCURRENT}"
echo "Requests/Second: ${REQUESTS_PER_SECOND}"
echo "=========================================="

# Get the route URL
echo -e "\n[1/5] Getting model route URL..."
ROUTE_URL=$(oc get route ${MODEL_NAME} -n ${NAMESPACE} -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
if [ -z "$ROUTE_URL" ]; then
    echo "Error: Route not found. Is the model deployed?"
    exit 1
fi
echo "Route URL: https://${ROUTE_URL}"

# Get authentication token
echo -e "\n[2/5] Getting authentication token..."
TOKEN=$(oc whoami -t)

# Check initial state
echo -e "\n[3/5] Initial state:"
echo "Pods:"
oc get pods -n ${NAMESPACE} -l serving.kserve.io/inferenceservice=${MODEL_NAME}
echo -e "\nHPA:"
oc get hpa -n ${NAMESPACE} -l serving.kserve.io/inferenceservice=${MODEL_NAME}

# Prepare test payload
PAYLOAD='{"inputs": "This is a test sentence for inference."}'

echo -e "\n[4/5] Starting load test..."
echo "This will run for ${DURATION} seconds and generate CPU load to trigger autoscaling."
echo "Watch the HPA and pods in another terminal with:"
echo "  watch -n 2 'oc get hpa,pods -n ${NAMESPACE}'"
echo ""

# Function to send requests
send_requests() {
    local end_time=$((SECONDS + DURATION))
    local request_count=0

    while [ $SECONDS -lt $end_time ]; do
        for i in $(seq 1 $REQUESTS_PER_SECOND); do
            curl -sk -X POST \
                "https://${ROUTE_URL}/v2/models/${MODEL_NAME}/infer" \
                -H "Authorization: Bearer ${TOKEN}" \
                -H "Content-Type: application/json" \
                -d "${PAYLOAD}" \
                > /dev/null 2>&1 &

            request_count=$((request_count + 1))
        done

        # Print progress every 10 seconds
        if [ $((SECONDS % 10)) -eq 0 ]; then
            echo "  [$(date +%T)] Sent ${request_count} requests... ($(( end_time - SECONDS ))s remaining)"
        fi

        sleep 1
    done

    wait
    echo "  Total requests sent: ${request_count}"
}

# Run the load test
send_requests

echo -e "\n[5/5] Load test completed. Checking final state..."
sleep 5

echo -e "\nPods after load:"
oc get pods -n ${NAMESPACE} -l serving.kserve.io/inferenceservice=${MODEL_NAME}

echo -e "\nHPA status after load:"
oc get hpa -n ${NAMESPACE} -l serving.kserve.io/inferenceservice=${MODEL_NAME}

echo -e "\nHPA detailed metrics:"
oc describe hpa -n ${NAMESPACE} -l serving.kserve.io/inferenceservice=${MODEL_NAME}

echo -e "\n=========================================="
echo "Test complete!"
echo "=========================================="
echo "The HPA will scale down automatically after the cooldown period (~5 minutes)"
echo "Monitor the scale-down with:"
echo "  watch -n 2 'oc get hpa,pods -n ${NAMESPACE}'"
echo ""
echo "To run another test with custom parameters:"
echo "  DURATION=600 REQUESTS_PER_SECOND=10 ./test-hpa-scaling.sh"
