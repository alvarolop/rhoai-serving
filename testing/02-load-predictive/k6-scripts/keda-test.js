// k6 KEDA Autoscaling Test Script
// Maintains constant concurrent load to trigger KEDA ScaledObject

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Counter, Trend, Rate } from 'k6/metrics';

// Custom metrics
const inferenceRequests = new Counter('inference_requests_total');
const inferenceLatency = new Trend('inference_latency_ms');
const inferenceErrors = new Rate('inference_errors');
const concurrentRequests = new Trend('concurrent_requests');

// Configuration from environment variables
const MODEL = __ENV.MODEL;
const ROUTE_URL = __ENV.ROUTE_URL;
const TOKEN = __ENV.TOKEN;

export const options = {
  scenarios: {
    keda_constant_load: {
      // KEDA monitors ovms_current_requests (concurrent requests)
      executor: 'constant-vus',
      vus: 20,              // 20 concurrent users
      duration: '5m',       // 5 minutes of constant load
    },
  },
  thresholds: {
    'http_req_duration': ['p(95)<5000'],
    'http_req_failed': ['rate<0.05'],
    'concurrent_requests': ['avg>10'],
  },
};

// KServe v2 inference protocol payload for DistilBERT (ONNX)
// Pre-tokenized: "KEDA testing with concurrent requests"
const payload = JSON.stringify({
  inputs: [
    {
      name: 'input_ids',
      shape: [1, 8],
      datatype: 'INT64',
      data: [[101, 14272, 5604, 2007, 10820, 6134, 102, 0]]
    },
    {
      name: 'attention_mask',
      shape: [1, 8],
      datatype: 'INT64',
      data: [[1, 1, 1, 1, 1, 1, 1, 0]]
    }
  ]
});

const params = {
  headers: {
    'Authorization': `Bearer ${TOKEN}`,
    'Content-Type': 'application/json',
  },
};

export default function () {
  const url = `https://${ROUTE_URL}/v2/models/${MODEL}/infer`;

  const startTime = Date.now();
  const response = http.post(url, payload, params);
  const duration = Date.now() - startTime;

  inferenceRequests.add(1);
  inferenceLatency.add(duration);
  concurrentRequests.add(__VU);

  const success = check(response, {
    'status is 200': (r) => r.status === 200,
  });

  if (!success) {
    inferenceErrors.add(1);
    console.error(`Request failed: ${response.status}`);
  }

  sleep(0.5);
}

export function setup() {
  console.log(`========================================`);
  console.log(`k6 KEDA Test Configuration`);
  console.log(`========================================`);
  console.log(`Model: ${MODEL}`);
  console.log(`Route URL: https://${ROUTE_URL}`);
  console.log(`Strategy: Constant 20 concurrent VUs`);
  console.log(`========================================`);
}

export function teardown(data) {
  console.log(`\n========================================`);
  console.log(`KEDA Test Completed`);
  console.log(`========================================`);
}
