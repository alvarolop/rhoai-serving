// k6 Autoscaling Load Test
// Works with both HPA and KEDA modes

import http from 'k6/http';
import { check } from 'k6';
import { Counter, Trend, Rate } from 'k6/metrics';

const inferenceRequests = new Counter('inference_requests_total');
const inferenceLatency = new Trend('inference_latency_ms');
const inferenceErrors = new Rate('inference_errors');

const MODEL = __ENV.MODEL;
const ROUTE_URL = __ENV.ROUTE_URL;
const TOKEN = __ENV.TOKEN;
const SCALING_MODE = __ENV.SCALING_MODE || 'hpa';

export const options = {
  scenarios: {
    load_test: {
      executor: 'constant-vus',
      vus: SCALING_MODE === 'keda' ? 20 : 25,
      duration: SCALING_MODE === 'keda' ? '5m' : '3m',
    },
  },
  thresholds: {
    'http_req_duration': ['p(95)<5000'],
    'http_req_failed': ['rate<0.1'],
  },
};

// KServe v2 protocol payload (pre-tokenized DistilBERT)
const payload = JSON.stringify({
  inputs: [
    {
      name: 'input_ids',
      shape: [1, 8],
      datatype: 'INT64',
      data: [[101, 7170, 5604, 2005, 1044, 2050, 5643, 102]]
    },
    {
      name: 'attention_mask',
      shape: [1, 8],
      datatype: 'INT64',
      data: [[1, 1, 1, 1, 1, 1, 1, 1]]
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

  const success = check(response, {
    'status is 200': (r) => r.status === 200,
  });

  if (!success) {
    inferenceErrors.add(1);
  }
}

export function setup() {
  console.log(`k6 Load Test - ${SCALING_MODE.toUpperCase()} mode`);
  console.log(`Model: ${MODEL}`);
  console.log(`Route: https://${ROUTE_URL}`);
}
