# RHOAI Serving

This repository showcases how to deploy Predictive and Generative AI models on OpenShift using RHOAI.

## Prerequisites

- OpenShift Container Platform 4.20+.
- OpenShift GitOps.
- OpenShift AI.

If you want to fast-forward the installation of your cluster, you can use these two repositories of mine:

- [ocp-on-aws](https://github.com/alvarolop/ocp-on-aws), to install an OpenShift cluster with auth, GitOps, Certificates and OCP-Lightspeed on AWS with just one click.
- [rhoai-gitops](https://github.com/alvarolop/rhoai-gitops), to install Red Hat OpenShift AI on your cluster with all the dependencies (OCP Pipelines, Kueue, Node Feature Discovery, Nvidia GPU Operator, Authorino, etc.) with just one click.

## Introduction

In this repository, we will showcase all the features of RHOAI Serving. Since OpenShift AI 3.0, the serving of models is configured differently based on the purpose of the model. Therefore, we will explore the following scenarios:

1. Serving **Predictive** models using OpenVINO.
2. Serving **Predictive** models using MLServer (Seldon).
3. Serving **Generative** models using vLLM.
4. Serving **Generative** models using vLLM and distributed across multiple GPUs.
5. Serving **Generative** models using vLLM and llm-d routing for inference acceleration.
6. Serving **Generative** models using vLLM and llm-d routing with prefill and decode disaggregation.
7. Serving **Embeddings** models using MLServer.
8. Serving **Vision Language Models** (VLMs) using vLLM.
9. Serving **Guardrails** models for TrustyAI.

> [!NOTE]
> Independently of the purpose of the model, we will use the `kserve` operator to serve the model using the **Raw deployment** mode since it is the most flexible and powerful mode.

After you deploy a model, run the matching script from the repository root (with `oc` logged in and `jq` installed) to confirm it responds:

- **Generative** (LLMInferenceService): [`tests/test-generative.sh`](tests/test-generative.sh) — arguments are `<namespace>` then the **LLMInferenceService object name** (the chart `name` in the model values file, e.g. `qwen3-8b`), not the Helm release name (e.g. `qwen`). If you pass a wrong name but there is only one LLMInferenceService in that namespace, the script uses it and prints a note. The script reads `spec.model.name` for the OpenAI `model` field; optional third argument overrides that id.
- **Predictive** (InferenceService): [`tests/test-predictive.sh`](tests/test-predictive.sh) — argument is the InferenceService name; the script uses namespace `model-<name>`.

## Architecture Components

The integrated KServe + llm-d + MLServer system comprises layered responsibilities:

| Component | Role |
|-----------|------|
| **KServe** | Model serving orchestration (Raw deployment mode) |
| **LLMInferenceService** | CRD for serving generative models |
| **llm-d** | Distributed inference framework for generative models |
| **MLServer** | Serving runtime for predictive models based on Seldon |
| **TrustyAI** | Guardrails model for TrustyAI |


> [!TIP]
> For more details, see the [KServe blog post on cloud-native AI inference with llm-d](https://kserve.github.io/website/blog/cloud-native-ai-inference-kserve-llm-d).

## Helm Chart Usage

The chart uses a **two-layer values** approach: defaults live in `values.yaml` (generative single-GPU vLLM), and each shipped model has a small file `values-<model>.yaml` next to it (same folder) with identity and overrides.

Deploy by combining the base defaults and one model file:

```bash
helm template <release> chart/ \
  -f chart/values.yaml \
  -f chart/values-<model>.yaml | oc apply -f -
```

Predictive models (for example DistilBERT) bundle their OpenVINO settings in their own file; you still pass `values.yaml` first, then that file.

### Namespace

Resources are created in `namespace.name`. By default the chart also creates a `Namespace` object with OpenShift console metadata:

```yaml
namespace:
  create: true
  name: model-qwen
  displayName: ""       # console short title; defaults to name if empty
  description: ""       # optional; openshift.io/description only when non-empty
  kueueManaged: true    # default: label namespace for Kueue (serving workloads use queues)
```

This chart assumes **Kueue** (Red Hat build) is installed and that model serving runs under queue enforcement. When the chart creates the namespace, it sets `kueue.openshift.io/managed=true` so Kueue applies (see [Managing workloads with Kueue](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/latest/html/managing_openshift_ai/managing-workloads-with-kueue)). Set `namespace.kueueManaged: false` only if you deliberately opt out.

To deploy into an **existing** namespace (no `Namespace` manifest), set `namespace.create: false` and point `namespace.name` at that namespace. Ensure that namespace already has `kueue.openshift.io/managed=true` (or add it) so serving stays under Kueue.

### HuggingFace Token for Gated Models

Some models hosted on HuggingFace (those using `hf://` URIs) require authentication to download. This applies to gated or private models like Granite, Llama, etc.

1. Create a `.hf_token` file in the repository root with your HuggingFace token:

```bash
echo "hf_your_token_here" > .hf_token
```

> [!NOTE]
> The `.hf_token` file is git-ignored. See `.hf_token.example` for the expected format.

2. Pass the token when deploying:

```bash
helm template granite chart/ \
  -f chart/values.yaml \
  -f chart/values-granite-4-0-h-tiny.yaml \
  --set hfToken=$(cat .hf_token) | oc apply -f -
```

This creates a `hf-secret` Kubernetes Secret and injects `HF_TOKEN` into the model container via `secretKeyRef`, following [KServe's recommended approach](https://kserve.github.io/website/docs/model-serving/storage/providers/hf).

> [!TIP]
> Models using `oci://` URIs (like Qwen3-8B from `registry.redhat.io`) do not need a HuggingFace token.

### Generative Models

**Qwen3-8B-FP8-dynamic** (single GPU, OCI registry - no HF token needed):

```bash
helm template qwen chart/ \
  -f chart/values.yaml \
  -f chart/values-qwen3-8b-fp8-dynamic.yaml | oc apply -f -
```

When the LLMInferenceService is ready:

```bash
./tests/test-generative.sh model-qwen qwen3-8b
```

**Granite 4.0 H Tiny FP8** (single GPU):

```bash
helm template granite chart/ \
  -f chart/values.yaml \
  -f chart/values-granite-4-0-h-tiny.yaml | oc apply -f -
```

When the LLMInferenceService is ready:

```bash
./tests/test-generative.sh model-granite granite-4-0-h-tiny
```

**Llama 3.1 70B** (4x GPU, HF token required):

```bash
helm template llama chart/ \
  -f chart/values.yaml \
  -f chart/values-llama-3.1-70b.yaml \
  --set hfToken=$(cat .hf_token) | oc apply -f -
```

When the LLMInferenceService is ready:

```bash
./tests/test-generative.sh model-llama llama-3-1-70b
```

<!--
TinyLlama docs paused until vLLM CPU / PyTorch `init_cpu_threads_env` issue is fixed on the platform (see vLLM#33675). Config files remain: chart/values-tinyllama-1b-gpu.yaml, chart/values-tinyllama-1b-cpu.yaml.

**TinyLlama 1B** (single small GPU; reliable path with current RHOAI vLLM images):

```bash
helm template tinyllama chart/ \
  -f chart/values.yaml \
  -f chart/values-tinyllama-1b-gpu.yaml | oc apply -f -
```

When the LLMInferenceService is ready:

```bash
./tests/test-generative.sh model-tinyllama tinyllama-1b
```

> [!WARNING]
> **CPU-only TinyLlama** (`VLLM_TARGET_DEVICE=cpu`) can fail on some platform images with `AttributeError: ... init_cpu_threads_env`. That comes from the vLLM V1 CPU worker expecting a PyTorch op that is not present in the inference image’s PyTorch build ([vLLM#33675](https://github.com/vllm-project/vllm/issues/33675)). It is not something this Helm chart can patch; use the GPU values file above, upgrade OpenShift AI when a fixed vLLM/PyTorch pair is available, or track Red Hat support/release notes for CPU generative serving.

To try **TinyLlama without GPU** anyway (after confirming your RHOAI version supports CPU vLLM):

```bash
helm template tinyllama chart/ \
  -f chart/values.yaml \
  -f chart/values-tinyllama-1b-cpu.yaml \
  --set serving.gpu=false \
  --set resources.limits.nvidia\\.com/gpu=null \
  --set resources.requests.nvidia\\.com/gpu=null | oc apply -f -
```
-->

### Predictive Models

**DistilBERT** (CPU-only, OpenVINO, with TrustyAI monitoring):

```bash
helm template distilbert chart/ \
  -f chart/values.yaml \
  -f chart/values-distilbert.yaml | oc apply -f -
```

When the InferenceService route is ready:

```bash
./tests/test-predictive.sh distilbert
```

### Extra Runtime Arguments

You can pass extra arguments to the model runtime via `extraArgs` in model value files or inline with `--set`:

- **Generative models**: Arguments are joined into the `VLLM_ADDITIONAL_ARGS` environment variable.
- **Predictive models**: Arguments are appended as container CLI arguments.

For example, vLLM tool/function calling (only if your **vLLM image** actually contains the template file under `.../vllm/transformers_utils/chat_templates/`; using a missing name makes the server exit at startup):

```yaml
extraArgs:
  - "--enable-auto-tool-choice"
  - "--tool-call-parser hermes"
  - "--chat-template <template.jinja>"
```

Granite 4 models should use the tokenizer template by default; Granite-3.3-specific template filenames are not bundled in every RHOAI / vLLM release.

You can also pass arbitrary environment variables via `extraEnv`:

```yaml
extraEnv:
  - name: VLLM_CONFIGURE_LOGGING
    value: "1"
```

### TrustyAI Monitoring

Enable [TrustyAI](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.3/html/monitoring_your_ai_systems/) for bias and data drift monitoring by setting `trustyai.enabled: true` in a model's values file. This deploys a `TrustyAIService` CR and the required `kserve-logger-ca-bundle` ConfigMap in the model's namespace.

```yaml
trustyai:
  enabled: true
```

TrustyAI supports PVC (default) or DATABASE storage backends. See `chart/values.yaml` for all configuration options.

> [!NOTE]
> Before enabling TrustyAI, ensure the TrustyAI component is enabled in your OpenShift AI Data Science Cluster and that monitoring is configured for the model serving platform.

## Nice references to read

- [Serving a Predictive model using Open Model Zoo](https://github.com/openvinotoolkit/open_model_zoo) is a collection of pre-trained models for various tasks.
- [LLMInferenceService Configuration Guide](https://kserve.github.io/website/docs/model-serving/generative-inference/llmisvc/llmisvc-configuration#complete-configuration-example)
- [Good example of llm-inference-service-pd-qwen2-7b-gpu.yaml](https://github.com/red-hat-data-services/kserve/blob/main/docs/samples/llmisvc/single-node-gpu/llm-inference-service-pd-qwen2-7b-gpu.yaml)
