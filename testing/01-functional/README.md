# Functional Testing

Quick validation scripts to verify models respond correctly to inference requests.

## Predictive Models (InferenceService)

Test predictive models using KServe v2 inference protocol:

```bash
./test-distilbert.sh
```

Works with OpenVINO models and other predictive workloads.

## Generative Models (LLMInferenceService)

Test generative models using OpenAI-compatible API:

```bash
./test-generative.sh <namespace> <llmis-name>

# Example
./test-generative.sh model-qwen3 qwen3-8b
```

Works with vLLM-based LLM models.

## Purpose

These scripts validate that:
- ✓ Models are accessible via routes
- ✓ Authentication works correctly
- ✓ Inference requests return valid responses
- ✓ Response structure matches expected format

For performance testing and autoscaling validation, see:
- [../02-load-predictive/](../02-load-predictive/) - HPA and KEDA testing
- [../03-load-generative/](../03-load-generative/) - GuideLLM (future)
