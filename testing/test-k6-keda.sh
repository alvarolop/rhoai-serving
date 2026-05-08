#!/bin/bash
# k6 wrapper script for KEDA testing (GPU-based predictive models with custom Prometheus metrics)
# Handles environment setup and monitoring

set -e

MODEL="${MODEL:-distilbert}"
NAMESPACE="${NAMESPACE:-model-distilbert}"

echo "=========================================="
echo "k6 Load Test - KEDA Autoscaling"
echo "=========================================="
echo "Model: ${MODEL}"
echo "Namespace: ${NAMESPACE}"
echo "=========================================="

# Check if k6 is installed
if ! command -v k6 &> /dev/null; then
    echo "Error: k6 not found. Install with:"
    echo "  sudo dnf install -y https://dl.k6.io/rpm/repo.rpm"
    echo "  sudo dnf install -y k6"
    exit 1
fi

# Get route and token
export TOKEN=$(oc whoami -t)
ROUTE_HOST=$(oc get route ${MODEL} -n ${NAMESPACE} -o jsonpath='{.spec.host}')
export ROUTE_HOST

echo "Route: https://${ROUTE_HOST}"
echo ""

# Show initial state
echo "Initial state:"
oc get scaledobject,pods -n ${NAMESPACE} 2>/dev/null || echo "No ScaledObject found (use mode: keda in values)"
echo ""

# Create k6 script for KEDA testing
cat > /tmp/k6-keda-test.js <<'EOFK6'
import http from 'k6/http';
import { check, sleep } from 'k6';
import { Counter, Trend, Rate } from 'k6/metrics';

const inferenceRequests = new Counter('inference_requests_total');
const inferenceLatency = new Trend('inference_latency_ms');
const inferenceErrors = new Rate('inference_errors');
const concurrentRequests = new Trend('concurrent_requests');

const MODEL = __ENV.MODEL;
const NAMESPACE = __ENV.NAMESPACE;
const TOKEN = __ENV.TOKEN;
const ROUTE_HOST = __ENV.ROUTE_HOST;
const BASE_URL = `https://${ROUTE_HOST}`;

export const options = {
  scenarios: {
    keda_constant_load: {
      // KEDA monitors ovms_current_requests (concurrent requests)
      // Use constant VUs to maintain concurrent load
      executor: 'constant-vus',
      vus: 20,              // 20 concurrent users
      duration: '5m',       // 5 minutes of constant load
    },
  },
  thresholds: {
    'http_req_duration': ['p(95)<5000'],  // GPU should be faster, but generous for KEDA
    'http_req_failed': ['rate<0.05'],
    'concurrent_requests': ['avg>10'],     // Should maintain concurrency
  },
};

const payload = JSON.stringify({
  inputs: 'KEDA testing with concurrent requests monitoring.'
});

const params = {
  headers: {
    'Authorization': `Bearer ${TOKEN}`,
    'Content-Type': 'application/json',
  },
};

export default function () {
  const url = `${BASE_URL}/v2/models/${MODEL}/infer`;

  const startTime = Date.now();
  const response = http.post(url, payload, params);
  const duration = Date.now() - startTime;

  inferenceRequests.add(1);
  inferenceLatency.add(duration);
  concurrentRequests.add(__VU);  // Track virtual users as proxy for concurrency

  const success = check(response, {
    'status is 200': (r) => r.status === 200,
  });

  if (!success) {
    inferenceErrors.add(1);
  }

  // Shorter sleep for KEDA - we want concurrent requests
  sleep(0.5);
}

export function setup() {
  console.log(`\nTesting KEDA autoscaling based on ovms_current_requests`);
  console.log(`Target: ${BASE_URL}/v2/models/${MODEL}/infer`);
  console.log(`Strategy: Maintain 20 concurrent virtual users\n`);
}
EOFK6

# Run k6 test
echo "=========================================="
echo "Starting k6 load test for KEDA..."
echo "Monitor KEDA ScaledObject in another terminal:"
echo "  watch -n 2 'oc get scaledobject,pods -n ${NAMESPACE}'"
echo ""
echo "Monitor Prometheus metric:"
echo "  oc exec -n ${NAMESPACE} <pod> -c kserve-container -- curl -s localhost:8001/metrics | grep ovms_current_requests"
echo "=========================================="
echo ""

k6 run /tmp/k6-keda-test.js \
  -e MODEL="${MODEL}" \
  -e NAMESPACE="${NAMESPACE}" \
  -e TOKEN="${TOKEN}" \
  -e ROUTE_HOST="${ROUTE_HOST}"

echo ""
echo "=========================================="
echo "Test completed!"
echo "=========================================="

# Show final state
echo ""
echo "Final state:"
oc get scaledobject,pods -n ${NAMESPACE} 2>/dev/null || echo "No ScaledObject found"

echo ""
echo "KEDA ScaledObject details:"
oc describe scaledobject -n ${NAMESPACE} 2>/dev/null | tail -25 || echo "No ScaledObject configured"

# Cleanup
rm -f /tmp/k6-keda-test.js

echo ""
echo "=========================================="
echo "KEDA will scale down based on pollingInterval"
echo "Monitor with: watch -n 2 'oc get scaledobject,pods -n ${NAMESPACE}'"
echo "=========================================="
