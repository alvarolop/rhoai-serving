# Scheduler tuning guide (llm-d EndpointPickerConfig)

**TL;DR**

- llm-d routes each request to one replica with the **Endpoint Picker (EPP)**. It scores replicas with a few scorer plugins; you tune the **weights**.
- RHOAI 3.5 default: `queue-scorer` 2, `kv-cache-utilization-scorer` 2, `prefix-cache-scorer` 3, `no-hit-lru-scorer` 2 (weights are relative).
- In this chart: set `serving.router.scheduler.endpointPickerConfig`. It is rendered into the ConfigMap `<name>-epp-config` and referenced from the `LLMInferenceService` (`router.scheduler.config.ref`).
- Only matters with **2 or more replicas**: with one replica there is nothing to choose.

## How a request is routed

```
Client ─▶ Inference Gateway ─▶ EPP ──────────────────────────────▶ vLLM replica
                                 ├─ Flow Control   (optional, feature gate) when/in what order to dispatch
                                 └─ Scheduling     (always on)              where to send it: scorers + picker
```

| Scorer | Prefers the replica that... |
|--------|-----------------------------|
| `prefix-cache-scorer` | already has the request's prompt prefix in its KV cache (hash based, works disconnected) |
| `queue-scorer` | has the shortest request queue |
| `kv-cache-utilization-scorer` | has the most free KV cache |
| `no-hit-lru-scorer` | is the least recently used, as a tiebreaker when nobody has a prefix hit |

Optional plugins in 3.5: `precise-prefix-cache-scorer` (token-level matching, needs a tokenizer sidecar that downloads models, so connected clusters only) and `latency-scorer` (lowest observed latency). Disaggregated prefill/decode (`spec.prefill`) gets its own scorer profiles automatically.

## Apply a configuration

```bash
# Uncomment one example in chart/values-scheduler-tuning-examples.yaml, then add it as a third overlay
helm template model chart/ \
  -f chart/values.yaml \
  -f chart/values-<model>.yaml \
  -f chart/values-scheduler-tuning-examples.yaml | oc apply -f -
```

The examples file is fully commented on purpose: as shipped it changes nothing. Restart the EPP pod after changing the ConfigMap.

Inline (`router.scheduler.config.inline`) and ConfigMap (`config.ref`) are mutually exclusive in the CRD; the chart always uses the ConfigMap.

## Strategies

All use `apiVersion: llm-d.ai/v1alpha1`, `kind: EndpointPickerConfig`, with the four scorers and `max-score-picker` declared under `plugins` (see the examples file for the full YAML). Only the weights change:

| Strategy | Use when | prefix | queue | kv-cache | no-hit-lru |
|----------|----------|:------:|:-----:|:--------:|:----------:|
| Default (3.5) | start here | 3 | 2 | 2 | 2 |
| Cache-optimized | multi-turn chat, repeated system prompts, RAG with shared context | 70 | 20 | 10 | 10 |
| Load-balanced | mixed request types and sizes, predictable latency | 33 | 33 | 34 | 10 |
| Queue-first | high volume, throughput over latency | 25 | 60 | 15 | 10 |
| Memory-aware | very long contexts, memory-constrained GPUs | 15 | 25 | 60 | 10 |

```yaml
schedulingProfiles:
  - name: default
    plugins:
      - pluginRef: prefix-cache-scorer
        weight: 70
      - pluginRef: queue-scorer
        weight: 20
      - pluginRef: kv-cache-utilization-scorer
        weight: 10
      - pluginRef: no-hit-lru-scorer
        weight: 10
```

Trade-off to expect: a heavy `prefix-cache-scorer` weight raises cache hits and lowers time to first token, but can concentrate load on a few replicas.

## Measure

Use the same load for every configuration and compare 10-15 minutes of steady traffic. On OpenShift with the Cluster Observability Operator, the built-in dashboards (**Observe & Monitor**, "LLM Traffic") cover traffic, latency and resource use; otherwise query Prometheus. Metric names as exposed by vLLM 0.2x (check **Observe > Metrics** if a query returns nothing):

```promql
# Time to first token, p50
histogram_quantile(0.5, sum by (le) (rate(vllm:time_to_first_token_seconds_bucket[5m])))
# Prefix cache hit rate
sum(rate(vllm:prefix_cache_hits_total[5m])) / sum(rate(vllm:prefix_cache_queries_total[5m]))
# Queue depth and KV cache usage
avg(vllm:num_requests_waiting)
avg(vllm:kv_cache_usage_perc)
# Request latency, p95
histogram_quantile(0.95, sum by (le) (rate(vllm:e2e_request_latency_seconds_bucket[5m])))
```

The EPP also exports service-level metrics with the `llm_d_epp_` prefix (time to first token, time per output token, inter-token latency, errors) that include scheduler wait and network time, the closest thing to what users feel.

## Troubleshooting

| Symptom | Try |
|---------|-----|
| High time-to-first-token variance | raise `queue-scorer` |
| Low cache hit rate | raise `prefix-cache-scorer`; check there are 2 or more replicas |
| Memory pressure or OOM | raise `kv-cache-utilization-scorer` |
| Uneven load across pods | lower `prefix-cache-scorer`, raise `queue-scorer` |

Change weights in steps of 10-20 points and re-measure. Saturation detection and priority queuing belong to the **Flow Control** layer, behind the `flowControl` feature gate of the EPP; this repo does not configure it.

## References

- [Configure request routing for llm-d (RHOAI 3.5)](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.5/html/deploy_models_using_distributed_inference_with_llm-d/configuring-llm-scheduler)
- [Monitor llm-d deployments (RHOAI 3.5)](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.5/html/deploy_models_using_distributed_inference_with_llm-d/monitoring-llmd-deployments)
- [llm-d inference scheduler architecture](https://github.com/llm-d/llm-d-inference-scheduler/blob/main/docs/architecture.md)
- Examples: `chart/values-scheduler-tuning-examples.yaml`
