# Intelligent Routing Test

This test validates that **intelligent routing** with llm-d EPP (Endpoint Picker) is working correctly for LLMInferenceService deployments.

> **Note**: All scripts in this test suite should be run from the **repository root** directory.

## What is Intelligent Routing?

Intelligent routing uses:
- **Prefix-aware scheduling**: Routes requests with shared prefixes to the same replica
- **KV cache-aware routing**: Considers cached context when selecting endpoints
- **Queue depth balancing**: Distributes load based on replica utilization

## Test Methodology

The test evaluates intelligent routing by:

### 1. Sending Requests with Shared Prefixes

We send 4 requests in 2 pairs:
- **Pair 1**: "Tell me about Paris" → "Tell me about Paris and its history"
- **Pair 2**: "Tell me about London" → "Tell me about London and its culture"

### 2. Measuring Time-to-First-Token (TTFT)

With intelligent routing:
- Request 1a creates cache entry
- Request 1b **reuses cache** → Lower TTFT (cache hit)
- Request 2a creates new cache entry
- Request 2b **reuses cache** → Lower TTFT (cache hit)

Without intelligent routing (round-robin):
- Requests distributed randomly
- No cache reuse
- Consistent TTFT across all requests

### 3. Collecting vLLM Metrics

The test collects metrics from `/metrics` endpoint on each vLLM pod:
- Cache hit/miss counts
- Prefix cache utilization
- Queue depth per replica

## Expected Results

### ✅ With Intelligent Routing Enabled

```
TTFT Comparison:
  Request 1a (Paris):              450ms
  Request 1b (Paris + history):    180ms (60% faster ✓)
  Request 2a (London):             470ms
  Request 2b (London + culture):   190ms (60% faster ✓)

Cache hit rate: ~50% (2/4 requests)
Shared prefix requests: Same pod ✓
```

### ❌ Without Intelligent Routing (Round-Robin)

```
TTFT Comparison:
  Request 1a (Paris):              450ms
  Request 1b (Paris + history):    460ms (no improvement)
  Request 2a (London):             440ms
  Request 2b (London + culture):   455ms (no improvement)

Cache hit rate: ~0%
Request distribution: Random across pods
```

## Prerequisites

- Deployed LLMInferenceService with **2+ replicas**
- Intelligent routing enabled: `serving.router.intelligentRouting.enabled: true`
- Access to the OpenShift cluster with `oc` CLI

## Usage

### Basic Test (run from repo root)

```bash
./testing/05-intelligent-routing/test-intelligent-routing.sh [DEPLOYMENT_NAME] [NAMESPACE] [MODEL_NAME]
```

### Example

```bash
# Test with default values (gpt-oss-20b)
./testing/05-intelligent-routing/test-intelligent-routing.sh

# Test with specific deployment
./testing/05-intelligent-routing/test-intelligent-routing.sh gpt-oss-20b model-gpt-oss gpt-oss-20b
```

## How to Verify Intelligent Routing

### 1. Check LLMInferenceService Configuration

```bash
oc get LLMInferenceService gpt-oss-20b -n model-gpt-oss -o yaml | grep -A 5 "router:"
```

**Expected output (intelligent routing enabled):**
```yaml
router:
  gateway:
    refs:
      - name: openshift-ai-inference
        namespace: openshift-ingress
  route: {}
  scheduler: {}  # ← This creates EPP for intelligent routing
```

**Without intelligent routing:**
```yaml
router:
  gateway: {}
  route: {}
  # No scheduler section → basic round-robin
```

### 2. Check InferencePool Created

When intelligent routing is enabled, KServe automatically creates an InferencePool:

```bash
oc get InferencePool -n model-gpt-oss
```

**Expected output:**
```
NAME          AGE
gpt-oss-20b   10m
```

### 3. Check EPP Deployment

The EPP (Endpoint Picker) scheduler runs as a separate deployment:

```bash
oc get deployment -n model-gpt-oss | grep epp
```

**Expected output:**
```
gpt-oss-20b-epp   1/1     1            1           10m
```

### 4. Manually Check vLLM Metrics

View cache metrics from a specific pod:

```bash
POD=$(oc get pods -n model-gpt-oss -l "app.kubernetes.io/name=gpt-oss-20b,app.kubernetes.io/component=llminferenceservice-workload" -o jsonpath='{.items[0].metadata.name}')

oc exec -n model-gpt-oss ${POD} -c main -- \
  curl -k -s https://localhost:8000/metrics | grep -E 'cache|prefix'
```

**Look for metrics like:**
- `vllm:prefix_cache_hit_rate` - Percentage of cache hits
- `vllm:cache_config_info` - Cache configuration
- `vllm:num_requests_waiting` - Queue depth

## Troubleshooting

### Issue: No TTFT improvement on shared prefix requests

**Possible causes:**
1. Intelligent routing disabled in values.yaml
2. Only 1 replica (no routing decisions needed)
3. EPP scheduler not running

**Check:**
```bash
# Verify scheduler section exists
oc get LLMInferenceService gpt-oss-20b -n model-gpt-oss -o yaml | grep scheduler

# Check EPP deployment
oc get deployment -n model-gpt-oss | grep epp

# Check EPP logs
oc logs -n model-gpt-oss deployment/gpt-oss-20b-epp
```

### Issue: All requests going to one pod

**Possible causes:**
1. Only 1 replica running
2. Other replicas not ready

**Check:**
```bash
# Count ready replicas
oc get pods -n model-gpt-oss -l serving.kserve.io/llminferenceservice=gpt-oss-20b

# Check pod status
oc get LLMInferenceService gpt-oss-20b -n model-gpt-oss -o jsonpath='{.status.replicas}'
```

### Issue: Cannot access /metrics endpoint

**Possible causes:**
1. vLLM metrics not exposed
2. Wrong container name

**Fix:**
```bash
# List containers in pod
oc get pod ${POD} -n model-gpt-oss -o jsonpath='{.spec.containers[*].name}'

# Try with correct container name
oc exec -n model-gpt-oss ${POD} -c kserve-container -- curl http://localhost:8000/metrics
```

## Comparison: With vs Without Intelligent Routing

| Metric | Intelligent Routing ON | Intelligent Routing OFF |
|--------|----------------------|------------------------|
| Cache hit rate | ~50% (shared prefixes) | ~0% (random distribution) |
| TTFT (cache hit) | 40-60% faster | No improvement |
| Request routing | Prefix-aware | Round-robin |
| EPP scheduler | Created automatically | Not created |
| InferencePool | Exists | Does not exist |

## Disable Intelligent Routing

To test without intelligent routing, update your values file:

```yaml
serving:
  router:
    intelligentRouting:
      enabled: false
```

Redeploy the model and run the test again to compare results.

## Related Documentation

- [KServe LLMInferenceService Configuration](https://kserve.github.io/website/docs/model-serving/generative-inference/llmisvc/llmisvc-configuration)
- [Red Hat Developer: Accelerate multi-turn workloads with llm-d](https://developers.redhat.com/articles/2026/01/13/accelerate-multi-turn-workloads-llm-d)
- [Gateway API Inference Extension - InferencePool](https://gateway-api-inference-extension.sigs.k8s.io/api-types/inferencepool/)
