# Load Testing for Generative Models

**Status**: Future implementation

This directory will contain load testing tools and scripts for generative AI models (LLMInferenceService).

## Planned Tools

### GuideLLM

GuideLLM will be used for LLM-specific benchmarking with metrics like:
- Tokens per second (throughput)
- Time to first token (TTFT)
- Inter-token latency
- End-to-end request latency

See [../README.md](../README.md#3-performance-testing---generative-models) for full documentation.

## Future Scripts

```bash
# Planned scripts (not yet implemented)
./test-guidellm.sh                # Basic GuideLLM test
./test-guidellm-wva.sh           # WVA autoscaling test
./run-guidellm-container.sh      # Containerized GuideLLM
```

## Why Not Use k6 for Generative?

k6 is excellent for predictive models but lacks LLM-specific features:
- ❌ No streaming response support for chat completions
- ❌ No token-level metrics (TTFT, tokens/s)
- ❌ No awareness of LLM-specific patterns (prompt caching, KV cache)

GuideLLM is purpose-built for LLM benchmarking and will provide better insights for generative workloads.
