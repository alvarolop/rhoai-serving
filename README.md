# RHOAI Serving

This repository showcases how to deploy Predictive and Generative AI models on OpenShift using RHOAI.

**Architecture notes** (routes, llm-d, naming, CPU worker overrides): see [docs/README.md](docs/README.md).

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

## Testing

Comprehensive testing guide covering functional validation, performance testing, and autoscaling:

**📖 [Testing Documentation](testing/README.md)**

Quick tests:
- **Functional - Predictive**: `testing/01-functional/test-distilbert.sh`
- **Functional - Generative**: `testing/01-functional/test-generative.sh`
- **Performance - HPA**: `testing/02-load-predictive/run-k6-container-hpa.sh`
- **Performance - KEDA**: `testing/02-load-predictive/run-k6-container-keda.sh`

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

Every model is deployed the same way: render the chart with `chart/values.yaml` plus one model overlay, and pipe it to `oc apply` (no Helm release is created).

```bash
helm template <name> chart/ -f chart/values.yaml -f chart/values-<model>.yaml | oc apply -f -
```

Run it from the repository root with `oc` logged in. All overlays deploy into the `models-as-a-service` namespace.

### Deploy a model

```bash
# ============================ GPU ============================

# Generative (vLLM, 1 GPU)
helm template qwen3-8b chart/ -f chart/values.yaml -f chart/values-qwen3-8b-fp8-dynamic.yaml | oc apply -f -
helm template gpt-oss-20b chart/ -f chart/values.yaml -f chart/values-gpt-oss-20b.yaml | oc apply -f -
helm template granite-4-0-h-tiny chart/ -f chart/values.yaml -f chart/values-granite-4-0-h-tiny.yaml | oc apply -f -
helm template devstral-small-2-24b-instruct chart/ -f chart/values.yaml -f chart/values-devstral-small-2-24b-instruct.yaml | oc apply -f -
helm template gemma-4-26b-a4b-fp8 chart/ -f chart/values.yaml -f chart/values-gemma-4-26b-a4b-fp8.yaml | oc apply -f -

# Generative (vLLM, multi-GPU: 4 GPUs)
helm template llama-3-1-70b chart/ -f chart/values.yaml -f chart/values-llama-3.1-70b.yaml --set-file hfToken=.hf_token | oc apply -f -
helm template qwen3-5-35b-a3b-gptq-int4 chart/ -f chart/values.yaml -f chart/values-qwen3.5-35b-a3b-gptq-int4.yaml | oc apply -f -

# Guardrails (1 GPU)
helm template granite-guardian-4-1-8b chart/ -f chart/values.yaml -f chart/values-granite-guardian-4.1-8b.yaml | oc apply -f -

# Embeddings (1 GPU)
helm template bge-m3 chart/ -f chart/values.yaml -f chart/values-bge-m3.yaml | oc apply -f -
helm template nomic-embed-text-v2-moe chart/ -f chart/values.yaml -f chart/values-nomic-embed-text-v2-moe-gpu.yaml | oc apply -f -

# Scheduler (EPP) tuning: add it as a third overlay on top of any generative model
helm template gpt-oss-20b chart/ -f chart/values.yaml -f chart/values-gpt-oss-20b.yaml -f chart/values-scheduler-tuning-examples.yaml | oc apply -f -

# ============================ CPU (no GPU needed) ============================

# Generative (vLLM CPU image)
helm template tinyllama-1b chart/ -f chart/values.yaml -f chart/values-tinyllama-1b.yaml | oc apply -f -
helm template granite-3-3-2b-instruct chart/ -f chart/values.yaml -f chart/values-granite-3-3-2b-instruct.yaml | oc apply -f -

# Embeddings (vLLM CPU image)
helm template nomic-embed-text-v1-cpu chart/ -f chart/values.yaml -f chart/values-nomic-embed-text-v1-cpu.yaml | oc apply -f -

# Predictive (OpenVINO + TrustyAI)
helm template distilbert chart/ -f chart/values.yaml -f chart/values-distilbert.yaml | oc apply -f -

# Model from S3 / MinIO / ODF (examples, CPU vLLM)
helm template tinyllama-s3-minio chart/ -f chart/values.yaml -f chart/values-example-minio-s3-tinyllama.yaml | oc apply -f -
helm template example-obc-model chart/ -f chart/values.yaml -f chart/values-example-odf-obc-s3.yaml | oc apply -f -
```

Only `hf://` models that are gated (Llama) need `--set-file hfToken=.hf_token`. See [Hugging Face token](#hugging-face-token).

### Test a model

```bash
testing/01-functional/test-generative.sh models-as-a-service gpt-oss-20b
NAMESPACE=models-as-a-service testing/01-functional/test-distilbert.sh
```

More tests (load, guardrails, routing, MaaS): [testing/README.md](testing/README.md).

### Remove a model

Same command with `oc delete`.:

```bash
helm template gpt-oss-20b chart/ -f chart/values.yaml -f chart/values-gpt-oss-20b.yaml | oc delete -f -
```

### Namespace

Resources go to `namespace.name`. The overlays use `create: false` (the namespace must already exist). Set `create: true` and the chart also renders the `Namespace`:

```yaml
namespace:
  create: true
  name: model-qwen
  displayName: ""       # console short title; defaults to name if empty
  description: ""       # optional
  kueueManaged: true    # label kueue.openshift.io/managed=true (serving runs under Kueue)
```

If you use an existing namespace, make sure it has `kueue.openshift.io/managed=true`. See [Kueue queues](#kueue-queues).

### Kueue queues

The cluster uses the *reserved-spot* queues from [rhoai-gitops](https://github.com/alvarolop/rhoai-gitops#kueue-queues-reserved-spot): `serving-cq` owns the GPUs (models), `batch-cq` borrows idle ones, and `cluster-queue` serves CPU workloads. Queues are selected through the HardwareProfile, and the chart only sets the matching `kueue.x-k8s.io/queue-name` label. The `ClusterQueue` and the `LocalQueue` objects (shared by every model in the namespace) are created by rhoai-gitops:

| `serving.hardwareProfile.name` | LocalQueue (label) | Priority (label) |
|---|---|---|
| `gpu-profile` | `serving-lq` | `model-critical` |
| `gpu-batch-profile` | `batch-lq` | `batch-nightly` |
| `cpu-profile` | `default` | none |

Override the labels with `kueue.localQueue` and `kueue.priorityClass` (for example `model-standard`). RHOAI 3.5 does not apply the HardwareProfile priority to an `LLMInferenceService`, hence the explicit label. The LocalQueue must exist in the namespace. If a pod stays `SchedulingGated`, check the Workload:

```bash
oc get workload -n models-as-a-service
oc describe workload -n models-as-a-service | grep -A3 QuotaReserved   # e.g. "LocalQueue serving-lq doesn't exist"
```

### Chart Documentation (helm-docs)

`chart/README.md` is generated from the `values.yaml` comments with [helm-docs](https://github.com/norwoodj/helm-docs) (see [`chart/HELM_DOCS.md`](chart/HELM_DOCS.md)):

```bash
cd chart/ && make docs
```

### Hugging Face token

Gated or private **`hf://`** checkpoints need a token. Put it in **`.hf_token`** (git-ignored; see **`.hf_token.example`**) or export **`HF_TOKEN`**. The chart creates **`hf-secret`** and mounts **`HF_TOKEN`** only when **`model.uri`** starts with **`hf://`** and **`hfToken`** is non-empty at render time ([KServe / Hugging Face storage](https://kserve.github.io/website/docs/model-serving/storage/providers/hf)). Public **`hf://`** models in this repo (for example Nomic) can deploy without a token.

> [!TIP]
> **`oci://`** ModelCars (Qwen3-8B, GPT-OSS 20B, Granite 4.0 H Tiny here) do not use Hugging Face download auth.

### Model notes

- **Embeddings** (`bge-m3`, `nomic-embed-text-v2-moe`): GPU, platform vLLM image, `gpu-profile`, `--task embedding`. Call `/v1/embeddings` with `spec.model.name`. See [vLLM pooling models](https://docs.vllm.ai/en/latest/models/pooling_models/embed/).
- **MaaS**: overlays that set `serving.routerGatewayRefs` (for example `maas-default-gateway` in `openshift-ingress`) attach to the MaaS gateway; list gateways with `oc get gateway.networking.k8s.io -A`. The namespace must be allowed by the gateway.
- **Guardrails**: `values-granite-guardian-4.1-8b.yaml`; the generative overlays can also enable `guardrails` (NeMo).

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
