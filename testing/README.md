# Testing Guide

Comprehensive testing strategies for KServe model serving on OpenShift AI.

---

## Table of Contents

1. [Functional Testing](#1-functional-testing) - Verify models respond correctly
2. [Performance Testing - Predictive Models](#2-performance-testing---predictive-models) - HPA and KEDA autoscaling
3. [Performance Testing - Generative Models](#3-performance-testing---generative-models) - GuideLLM (future)

---

## 1. Functional Testing

**Goal**: Verify that deployed models respond to inference requests correctly and return valid predictions.

### Quick Test: DistilBERT

Test the DistilBERT predictive model with a sample inference request:

```bash
cd testing
./test-distilbert.sh
```

**What it does:**
- Sends a sample text classification request
- Validates HTTP 200 response
- Displays the inference output (predictions/scores)
- Checks response time

**Example output:**
```json
{
  "model_name": "distilbert",
  "outputs": [
    {
      "name": "output",
      "shape": [1, 2],
      "data": [0.95, 0.05],
      "datatype": "FP32"
    }
  ]
}
```

### Testing Other Models

```bash
# Test with custom model
MODEL=my-model NAMESPACE=my-namespace ./test-distilbert.sh

# Test with custom payload
PAYLOAD='{"inputs": "Custom test sentence"}' ./test-distilbert.sh
```

---

## 2. Performance Testing - Predictive Models

**Goal**: Test autoscaling behavior (HPA and KEDA) under load for CPU/GPU predictive models.

### Load Testing Framework Comparison

| Framework | Best For | Complexity | Prometheus | Distributed |
|-----------|----------|------------|------------|-------------|
| **k6** ⭐ | HPA + KEDA, production testing | Medium | ✓ Yes | Yes (paid) |
| **Vegeta** | Quick benchmarks, simple HPA tests | Low | ✗ No | No |
| **Locust** | Complex workflows, Python teams | High | ~ Plugin | ✓ Yes |

**Recommendation**: Use **k6** for both HPA (CPU) and KEDA (GPU) testing because:
- Native Prometheus export (critical for KEDA validation)
- Flexible load patterns (ramping for HPA, constant for KEDA)
- High performance for GPU workload testing
- Same framework for both scenarios

**Official k6 Container Image**: [`docker.io/grafana/k6`](https://hub.docker.com/r/grafana/k6)

### Containerized k6 Testing (No Local Installation)

**Two approaches for running k6 without local installation:**

#### Option 1: Podman/Docker (Local Container)

Run k6 in a container with scripts mounted as volumes:

```bash
cd testing

# HPA test
./run-k6-container-hpa.sh

# KEDA test
./run-k6-container-keda.sh

# Custom model
MODEL=my-model NAMESPACE=my-namespace ./run-k6-container-hpa.sh
```

**How it works:**
- Mounts `k6-scripts/` directory into container
- Passes environment variables (MODEL, ROUTE_URL, TOKEN)
- No local k6 installation needed
- Uses official `grafana/k6` image

#### Option 2: OpenShift Job (Cloud-Native)

Run k6 as a Kubernetes Job directly in OpenShift:

```bash
cd testing

# HPA test
./run-k6-job-hpa.sh

# KEDA test
./run-k6-job-keda.sh

# Custom model
MODEL=my-model NAMESPACE=my-namespace ./run-k6-job-hpa.sh
```

**How it works:**
- Creates ConfigMap with k6 scripts (`manifests/configmap-k6-scripts.yaml`)
- Creates Secret with auth token
- Launches Job with `grafana/k6` image
- Follows job logs automatically
- Runs entirely in OpenShift (no local dependencies)

**OpenShift Best Practices Applied:**
- ✓ Non-root container (k6 runs as UID 12345)
- ✓ Read-only script volumes (`:ro`)
- ✓ Security context with dropped capabilities
- ✓ Resource limits (CPU: 1 core, Memory: 512Mi)
- ✓ Auto-cleanup with `ttlSecondsAfterFinished`
- ✓ Seccomp profile (RuntimeDefault)
- ✓ No privilege escalation

**Job Manifests:**
- `manifests/configmap-k6-scripts.yaml` - k6 test scripts
- `manifests/job-k6-hpa.yaml` - HPA test Job
- `manifests/job-k6-keda.yaml` - KEDA test Job

### 2.1 HPA Testing (CPU-based Autoscaling)

**Scenario**: CPU-based predictive model with Kubernetes HPA (e.g., DistilBERT on CPU).

**How HPA works:**
1. k6 generates ramping load (0 → 50 virtual users)
2. CPU utilization increases (targets 80% of request)
3. HPA detects CPU > 80% → scales from 1 to 5 replicas
4. Load decreases → HPA scales down after cooldown (~5 min)

**Run HPA test (containerized - recommended):**
```bash
cd testing

# Option 1: Run with podman/docker
./run-k6-container-hpa.sh

# Option 2: Run as OpenShift Job
./run-k6-job-hpa.sh

# Custom model
MODEL=my-model NAMESPACE=my-namespace ./run-k6-container-hpa.sh
```

**Alternative: Local k6 installation (legacy)**
```bash
sudo dnf install -y k6
./test-k6-hpa.sh  # Requires local k6 binary
```

**Monitor in another terminal:**
```bash
watch -n 2 'oc get hpa,pods -n model-distilbert'
```

**What to expect:**
- Initial: 1 pod, CPU 0-5%
- After 1-2 min: CPU > 80%, HPA triggers scale-up
- After 2-3 min: 2-5 pods running
- After load ends: Gradual scale-down over ~5 minutes

**Alternative: Vegeta (simpler, no Prometheus)**
```bash
# Quick benchmark with Vegeta
RATE=50/1s DURATION=180s ./test-vegeta.sh
```

### 2.2 KEDA Testing (Custom Metrics Autoscaling)

**Scenario**: GPU/CPU predictive model with KEDA ScaledObject monitoring Prometheus metrics (e.g., `ovms_current_requests`).

**How KEDA works:**
1. k6 generates constant concurrent load (20 virtual users)
2. `ovms_current_requests` metric increases in Prometheus
3. KEDA ScaledObject queries Prometheus via Thanos Querier
4. KEDA detects metric > threshold (e.g., 2) → scales replicas
5. Load decreases → KEDA scales down based on pollingInterval

**Prerequisites:**
- Model deployed with `scaling.mode: keda` in values file
- KEDA operator installed in cluster
- ScaledObject created (chart does this automatically)

**Run KEDA test (containerized - recommended):**
```bash
cd testing

# Option 1: Run with podman/docker
./run-k6-container-keda.sh

# Option 2: Run as OpenShift Job
./run-k6-job-keda.sh

# Custom model
MODEL=my-model NAMESPACE=my-namespace ./run-k6-container-keda.sh
```

**Alternative: Local k6 (legacy)**
```bash
sudo dnf install -y k6
./test-k6-keda.sh  # Requires local k6 binary
```

**Monitor KEDA scaling:**
```bash
# Watch ScaledObject and pods
watch -n 2 'oc get scaledobject,pods -n model-distilbert'

# Check Prometheus metric directly
oc exec -n model-distilbert <pod-name> -c kserve-container -- \
  curl -s localhost:8001/metrics | grep ovms_current_requests
```

**What to expect:**
- Initial: 1 pod, `ovms_current_requests` = 0-1
- During load: `ovms_current_requests` > 2 (threshold)
- KEDA scales: 1 → 2+ pods
- After load: Scale-down based on `pollingInterval` (default 5s)

**KEDA vs HPA differences:**

| Feature | HPA | KEDA |
|---------|-----|------|
| **Metrics** | CPU/Memory only | Any Prometheus metric |
| **Scaling trigger** | Resource utilization % | Custom PromQL query |
| **Best for** | Simple CPU/memory scaling | Inference-aware scaling |
| **Operator required** | No (native K8s) | Yes (KEDA operator) |
| **Use case** | General workloads | ML inference, GPU models |

### Load Testing Tips

**CPU request sizing for HPA testing:**
- Too high (1 CPU): Hard to trigger 80% utilization
- Too low (10m): Every request triggers scaling (unstable)
- **Sweet spot**: 50-100m CPU request for demo/testing
- **Production**: Size based on actual model CPU usage

**Request rate guidelines:**
```bash
# Light load (warm-up)
RATE=10/1s DURATION=60s

# Medium load (trigger HPA)
RATE=50/1s DURATION=180s

# Heavy load (stress test, trigger KEDA)
RATE=100/1s DURATION=300s
```

**Monitoring commands:**
```bash
# HPA status
oc get hpa -n <namespace>
oc describe hpa <hpa-name> -n <namespace>

# KEDA status
oc get scaledobject -n <namespace>
oc describe scaledobject <name> -n <namespace>

# Pod CPU usage (requires metrics-server)
oc adm top pods -n <namespace>

# Prometheus metrics from pod
oc exec -n <namespace> <pod> -c kserve-container -- curl -s localhost:8001/metrics
```

---

## 3. Performance Testing - Generative Models

**Status**: Future implementation (theory documented below)

### GuideLLM Overview

**GuideLLM** is a specialized benchmarking tool designed specifically for **Large Language Model (LLM)** inference workloads.

**GitHub**: https://github.com/neuralmagic/guidellm

**Key Features:**
- **LLM-specific metrics**: Tokens/second, time-to-first-token (TTFT), inter-token latency
- **OpenAI API compatible**: Works with vLLM, TGI, any OpenAI-compatible endpoint
- **Automated benchmarking**: Runs multiple scenarios with different concurrency levels
- **Request profiles**: Supports various input/output token distributions
- **Detailed reports**: JSON, CSV, and HTML output with visualizations

### Why GuideLLM for Generative Models?

| Metric | GuideLLM | k6/Vegeta |
|--------|----------|-----------|
| **Tokens/second** | ✓ Native | ✗ Manual calculation |
| **TTFT** | ✓ Native | ✗ Not measured |
| **Inter-token latency** | ✓ Native | ✗ Not measured |
| **Request latency** | ✓ Yes | ✓ Yes |
| **Streaming support** | ✓ Yes | ~ Partial |
| **LLM-aware scenarios** | ✓ Built-in | ✗ Manual |

**Why NOT GuideLLM for predictive models:**
- ❌ Designed for text generation (tokens), not classification/embeddings
- ❌ Expects OpenAI chat/completions API, not KServe v2 protocol
- ❌ Metrics (TTFT, tokens/s) don't apply to predictive workloads

### GuideLLM Use Cases (Future)

1. **Generative model serving** (`serving.type: generative`)
   - vLLM-based LLMInferenceService
   - OpenAI-compatible endpoints
   - Chat completions and text generation

2. **WVA Autoscaling testing** (when available)
   - Workload Variant Autoscaler (inference-aware)
   - Scale based on queue depth and token throughput
   - LLM-specific scaling policies

3. **Router testing** (llm-d integration)
   - Multi-replica routing
   - Load balancing strategies
   - Request scheduling

### Future Implementation Plan

When we implement generative model testing with GuideLLM:

```bash
# Install GuideLLM
pip install guidellm

# Run benchmark against vLLM model
testing/test-guidellm.sh \
  --model qwen3-8b \
  --namespace model-qwen3 \
  --max-concurrency 50 \
  --duration 300

# Test WVA autoscaling
testing/test-guidellm-wva.sh \
  --model qwen3-8b \
  --namespace model-qwen3 \
  --watch-wva
```

**GuideLLM will measure:**
- Output token throughput (tokens/second)
- Time to first token (TTFT)
- End-to-end latency
- Request success rate
- WVA scaling behavior (queue depth, scaling latency)

**Target metrics for generative models:**
- **TTFT**: < 500ms (good UX for chat)
- **Throughput**: > 1000 tokens/s (per GPU)
- **P95 latency**: < 2s for short prompts
- **WVA scaling**: < 30s from queue spike to new replica ready

---

## Summary

| Test Type | Tool | Target | Metrics |
|-----------|------|--------|---------|
| **Functional** | curl/bash | All models | Response correctness |
| **Predictive HPA** | k6 | CPU models | CPU %, replica count |
| **Predictive KEDA** | k6 | GPU models | `ovms_current_requests`, replicas |
| **Generative** | GuideLLM | vLLM models | Tokens/s, TTFT, latency |

**Quick Start:**
1. Functional test: `./test-distilbert.sh`
2. HPA test: `./test-k6-hpa.sh`
3. KEDA test: Deploy with `mode: keda`, then `./test-k6-keda.sh`
4. Generative: (Coming soon with GuideLLM)
