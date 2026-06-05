# Scheduler Tuning Guide for Performance Testing

Guide for tuning the llm-d EndpointPickerConfig scheduler to optimize inference performance.

## Overview

RHOAI 3.4+ uses the **llm-d EPP (EndPoint Picker)** scheduler for intelligent request routing across model replicas. The scheduler scores each pod based on:

1. **Prefix Cache Affinity** - Routes requests to pods with matching KV cache prefixes
2. **Queue Depth** - Avoids pods with long request queues
3. **KV Cache Utilization** - Prevents routing to memory-saturated pods

## Default Behavior

By default (`scheduler: {}`), RHOAI uses balanced weights:
- Prefix cache: ~40%
- Queue depth: ~30%
- KV utilization: ~30%

This works well for most workloads but can be tuned for specific use cases.

## Quick Start

### 1. Deploy with Custom Configuration

```bash
# Apply a tuning example on top of your model
helm template model chart/ \
  -f chart/values.yaml \
  -f chart/values-<your-model>.yaml \
  -f chart/values-scheduler-tuning-examples.yaml | oc apply -f -
```

### 2. Run Load Test

Use consistent load patterns to compare configurations:
```bash
# Example: 100 requests with shared prefixes
for i in {1..100}; do
  curl -X POST "https://<model-route>/v1/chat/completions" \
    -H "Authorization: Bearer $TOKEN" \
    -d '{
      "model": "model-name",
      "messages": [{"role": "user", "content": "Tell me about Paris"}],
      "max_tokens": 50
    }'
done
```

### 3. Monitor Grafana Dashboards

Key metrics to track:

**Time to First Token (TTFT):**
```promql
histogram_quantile(0.5, 
  rate(vllm_time_to_first_token_seconds_bucket[5m])
)
```

**Cache Hit Rate:**
```promql
rate(vllm_cache_hit_total[5m]) / 
rate(vllm_cache_access_total[5m]) * 100
```

**Queue Depth:**
```promql
avg(vllm_num_requests_waiting)
```

**KV Cache Utilization:**
```promql
avg(vllm_gpu_cache_usage_perc) / 100
```

**Request Latency (p95):**
```promql
histogram_quantile(0.95, 
  rate(vllm_request_duration_seconds_bucket[5m])
)
```

## Tuning Strategies

### Cache-Optimized (Conversational Workloads)

**Use when:**
- Multi-turn conversations
- Repeated system prompts
- RAG with consistent contexts

**Configuration:**
```yaml
serving:
  router:
    scheduler:
      endpointPickerConfig:
        apiVersion: inference.networking.x-k8s.io/v1alpha1
        kind: EndpointPickerConfig
        plugins:
          - type: prefix-cache-scorer
            parameters:
              blockSizeTokens: 5
              maxPrefixBlocksToMatch: 256
          - type: queue-scorer
          - type: kv-cache-utilization-scorer
          - type: max-score-picker
        schedulingProfiles:
          - name: default
            plugins:
              - pluginRef: prefix-cache-scorer
                weight: 70  # Maximize cache affinity
              - pluginRef: queue-scorer
                weight: 20
              - pluginRef: kv-cache-utilization-scorer
                weight: 10
```

**Expected improvements:**
- ✅ 30-50% TTFT reduction on cache hits
- ✅ 2-3x cache hit rate increase
- ⚠️ May concentrate load on fewer pods

### Load-Balanced (Mixed Workloads)

**Use when:**
- Varied request types
- Variable request sizes
- Need predictable latency

**Configuration:**
```yaml
schedulingProfiles:
  - name: default
    plugins:
      - pluginRef: prefix-cache-scorer
        weight: 33  # Equal weighting
      - pluginRef: queue-scorer
        weight: 33
      - pluginRef: kv-cache-utilization-scorer
        weight: 34
```

**Expected improvements:**
- ✅ Even request distribution
- ✅ Lower latency variance (p95/p99)
- ✅ Better resource utilization

### Queue-First (High Throughput)

**Use when:**
- High request volume
- Need to minimize queuing
- Throughput > latency priority

**Configuration:**
```yaml
schedulingProfiles:
  - name: default
    plugins:
      - pluginRef: queue-scorer
        weight: 60  # Avoid queued pods
      - pluginRef: prefix-cache-scorer
        weight: 25
      - pluginRef: kv-cache-utilization-scorer
        weight: 15
```

**Expected improvements:**
- ✅ Lower average queue depth
- ✅ Higher throughput (req/sec)
- ✅ More predictable latency

### Memory-Aware (Large Context Windows)

**Use when:**
- Large context (128k+ tokens)
- Memory-constrained GPUs
- Need to prevent OOM

**Configuration:**
```yaml
schedulingProfiles:
  - name: default
    plugins:
      - pluginRef: kv-cache-utilization-scorer
        weight: 60  # Avoid memory saturation
      - pluginRef: queue-scorer
        weight: 25
      - pluginRef: prefix-cache-scorer
        weight: 15
```

**Expected improvements:**
- ✅ Lower KV cache peaks
- ✅ Fewer OOM errors
- ✅ Better memory distribution

## Advanced: Saturation Detection

Prevent routing to overloaded pods:

```yaml
plugins:
  - type: utilization-detector
    parameters:
      queueDepthThreshold: 8      # Max queue before "saturated"
      kvCacheUtilThreshold: 0.85  # Max KV util before "saturated"
      headroom: 0.15              # Safety margin

saturationDetector:
  pluginRef: utilization-detector
```

When a pod exceeds thresholds, EPP stops routing new requests to it until utilization drops.

## Testing Workflow

### 1. Establish Baseline

Deploy with defaults and capture metrics for 10-15 minutes of steady load.

### 2. Apply Tuned Configuration

Deploy with modified weights for your use case.

### 3. Compare Metrics

Create Grafana comparison dashboard:
- TTFT (p50, p95, p99)
- Cache hit rate
- Queue depth (avg, max)
- KV utilization (avg, max)
- Request latency distribution

### 4. Iterate

Adjust weights in 10-20 point increments and re-test.

## Common Patterns

**Multi-turn chat (with system prompt):**
```yaml
# High cache affinity for repeated system prompts
prefix-cache-scorer: 70
queue-scorer: 20
kv-cache-utilization-scorer: 10
```

**RAG with shared context:**
```yaml
# Balance cache and queue (context reuse + varied queries)
prefix-cache-scorer: 50
queue-scorer: 30
kv-cache-utilization-scorer: 20
```

**Code generation (long outputs):**
```yaml
# Prioritize memory and queue
queue-scorer: 45
kv-cache-utilization-scorer: 35
prefix-cache-scorer: 20
```

**Mixed production workload:**
```yaml
# Balanced for stability
prefix-cache-scorer: 33
queue-scorer: 33
kv-cache-utilization-scorer: 34
```

## Troubleshooting

**High TTFT variance:**
- Increase `queue-scorer` weight
- Add saturation detection

**Low cache hit rate:**
- Increase `prefix-cache-scorer` weight
- Ensure replicas > 1 for intelligent routing

**OOM errors:**
- Increase `kv-cache-utilization-scorer` weight
- Lower `kvCacheUtilThreshold` in saturation detector

**Uneven pod load:**
- Decrease `prefix-cache-scorer` weight
- Increase `queue-scorer` weight

## References

- [llm-d Architecture](https://github.com/llm-d/llm-d-inference-scheduler/blob/main/docs/architecture.md)
- [KServe LLMInferenceService Configuration](https://kserve.github.io/website/docs/model-serving/generative-inference/llmisvc/llmisvc-configuration)
- [Gateway API EPP Configuration](https://gateway-api-inference-extension.sigs.k8s.io/guides/epp-configuration/config-text/)
- [RHOAI 3.4 Distributed Inference Docs](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self_managed/3.4/html/deploy_models_using_distributed_inference_with_llm-d/)

## Example Values Files

See `chart/values-scheduler-tuning-examples.yaml` for ready-to-use configurations:
- Example 1: Default baseline
- Example 2: Cache-optimized
- Example 3: Load-balanced
- Example 4: Queue-first
- Example 5: Memory-aware

Apply as overlay:
```bash
helm template model chart/ \
  -f chart/values.yaml \
  -f chart/values-<model>.yaml \
  -f chart/values-scheduler-tuning-examples.yaml
```
