#!/bin/bash
# k6 wrapper script for HPA testing (CPU-based predictive models)
# Handles environment setup and monitoring

set -e

MODEL="${MODEL:-distilbert}"
NAMESPACE="${NAMESPACE:-model-distilbert}"

echo "=========================================="
echo "k6 Load Test - HPA Autoscaling"
echo "=========================================="
echo "Model: ${MODEL}"
echo "Namespace: ${NAMESPACE}"
echo "=========================================="

# Check if k6 is installed
if ! command -v k6 &> /dev/null; then
    echo "Error: k6 not found. Install with:"
    echo "  sudo dnf install -y https://dl.k6.io/rpm/repo.rpm"
    echo "  sudo dnf install -y k6"
    echo ""
    echo "Or download from: https://k6.io/docs/getting-started/installation/"
    exit 1
fi

# Get route and token
export TOKEN=$(oc whoami -t)
ROUTE_HOST=$(oc get route ${MODEL} -n ${NAMESPACE} -o jsonpath='{.spec.host}')
export ROUTE_HOST

echo "Route: https://${ROUTE_HOST}"
echo "Token: ${TOKEN:0:20}..."
echo ""

# Show initial state
echo "Initial state:"
oc get hpa,pods -n ${NAMESPACE} -l serving.kserve.io/inferenceservice=${MODEL}
echo ""

# Create k6 script with inline config
cat > /tmp/k6-hpa-test.js <<'EOFK6'
import http from 'k6/http';
import { check, sleep } from 'k6';
import { Counter, Trend, Rate } from 'k6/metrics';

const inferenceRequests = new Counter('inference_requests_total');
const inferenceLatency = new Trend('inference_latency_ms');
const inferenceErrors = new Rate('inference_errors');

const MODEL = __ENV.MODEL;
const NAMESPACE = __ENV.NAMESPACE;
const TOKEN = __ENV.TOKEN;
const ROUTE_HOST = __ENV.ROUTE_HOST;
const BASE_URL = `https://${ROUTE_HOST}`;

export const options = {
  scenarios: {
    hpa_ramp: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '30s', target: 5 },    // Warm up
        { duration: '1m', target: 30 },    // Ramp to trigger HPA
        { duration: '2m', target: 30 },    // Sustain load
        { duration: '30s', target: 50 },   // Spike
        { duration: '1m', target: 50 },    // Sustain spike
        { duration: '1m', target: 0 },     // Ramp down
      ],
    },
  },
  thresholds: {
    'http_req_duration': ['p(95)<3000'],
    'http_req_failed': ['rate<0.05'],
    'inference_errors': ['rate<0.05'],
  },
};

const payload = JSON.stringify({
  inputs: 'Load testing for HPA autoscaling demonstration.'
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

  const success = check(response, {
    'status is 200': (r) => r.status === 200,
    'latency < 3s': (r) => r.timings.duration < 3000,
  });

  if (!success) {
    inferenceErrors.add(1);
  }

  sleep(1);
}

export function setup() {
  console.log(`Testing: ${BASE_URL}/v2/models/${MODEL}/infer`);
}
EOFK6

# Run k6 test
echo "=========================================="
echo "Starting k6 load test..."
echo "Monitor HPA in another terminal:"
echo "  watch -n 2 'oc get hpa,pods -n ${NAMESPACE}'"
echo "=========================================="
echo ""

k6 run /tmp/k6-hpa-test.js \
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
oc get hpa,pods -n ${NAMESPACE} -l serving.kserve.io/inferenceservice=${MODEL}

echo ""
echo "HPA details:"
oc describe hpa -n ${NAMESPACE} -l serving.kserve.io/inferenceservice=${MODEL} | tail -20

# Cleanup
rm -f /tmp/k6-hpa-test.js

echo ""
echo "=========================================="
echo "HPA will scale down after ~5 min of low load"
echo "Monitor with: watch -n 2 'oc get hpa,pods -n ${NAMESPACE}'"
echo "=========================================="
