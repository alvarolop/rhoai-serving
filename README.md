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

After you deploy a model, run the matching script from the repository root (with `oc` logged in and `jq` installed) to confirm it responds:

- **Generative** (LLMInferenceService): [`tests/test-generative.sh`](tests/test-generative.sh) — arguments are `<namespace>` then the **LLMInferenceService object name** (the chart `name` in the model values file, e.g. `qwen3-8b`), not Helm’s `.Release.Name` from `./deploy-mode.sh`. If you pass a wrong name but there is only one LLMInferenceService in that namespace, the script uses it and prints a note. The script reads `spec.model.name` for the OpenAI `model` field; optional third argument overrides that id.
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

The chart merges **`chart/values.yaml`** with one overlay **`chart/values-<model>.yaml`** (identity, URI, resources, and so on).

### Deploy (`deploy-mode.sh`)

From the repository root, with `oc` pointing at your cluster:

```bash
./deploy-mode.sh chart/values-<model>.yaml
```

This runs `helm template chart --generate-name -f chart/values.yaml -f <overlay> … | oc apply -f -`. Anything after the overlay path is passed straight to **`helm template`** (for example **`--set-json`** for MaaS gateways, or **`--set-file hfToken=.hf_token`** for gated **`hf://`** models).

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

#### Kueue: pods `Pending` with `SchedulingGated` (`kueue.x-k8s.io/topology`)

If the **Workload** is **Admitted** but pods never leave **Pending** (gates **admission** + **topology**), Kueue **Topology Aware Scheduling** is waiting for a **topology assignment** that never arrives because the **ResourceFlavor** had no **`spec.topologyName`** linked to a **`Topology`** object. **rhoai-gitops** (`rhoai-installation-chart`) now ships a minimal **hostname-level** `Topology` and sets **`topologyName`** (+ required **`nodeLabels`**) on **`cpu-flavor`** and **`gpu-flavor`** when **`distributedWorkloads.topologyAwareScheduling`** is **true** (default). Sync that chart, then verify:

```bash
oc get topology.kueue.x-k8s.io
oc get resourceflavor.kueue.x-k8s.io gpu-flavor -o yaml | grep -E 'topologyName|nodeLabels' -A2
```

If your GPU nodes do not carry **`nvidia.com/gpu.deploy.device-plugin=true`**, change the **hardcoded** `nodeLabels` in **`rhoai-installation-chart/templates/05-distributed-workloads/resourceflavor-gpu-flavor.yaml`**. To opt out of TAS wiring entirely (not recommended if you hit the deadlock), set **`distributedWorkloads.topologyAwareScheduling: false`** in **`rhoai-installation-chart/values.yaml`**.

Single-replica serving stays **`replicas: 1`** in **`chart/values.yaml`**; per-model files only override when you need more than one pod.

### Dashboard connection secret

The chart emits a **Secret** named **`name`**, matching **`opendatahub.io/connections`** on the serving CR. It follows the OpenShift AI **connections API** ([Using the connections API](https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed/3.2/html/working_on_projects/using-connections_projects)):

| `model.connection.protocol` | When | Secret |
|------------------------------|------|--------|
| **`uri`** (or **`auto`** when **`model.uri`** does not start with **`oci://`** and legacy OCI fields below are not both set) | `hf://`, `http(s)://`, `pvc://`, or a single **`model.uri`** string the console treats as URI-shaped (including **`s3://…`** if you use that style) | **`type: Opaque`**, label **`opendatahub.io/dashboard`**, annotations **`opendatahub.io/connection-type-protocol: uri`**, **`opendatahub.io/connection-type-ref: uri-v1`**, **`data.URI`** = base64(**`model.uri`**). |
| **`oci`** (or **`auto`** when **`model.uri`** starts with **`oci://`**, or legacy **`model.connection.oci.dockerconfigjson`** + **`host`** are both non-empty) | **`oci://`** ModelCar images | **`type: Opaque`**, label **`opendatahub.io/dashboard`**, annotations **`…-protocol: oci`**, **`…-ref: oci-v1`**, **`data.OCI_HOST`** = base64(**`model.uri`**). Optional **`data[".dockerconfigjson"]`** when **`model.connection.oci.dockerconfigjson`** is set (private registry). |
| **`s3`** (explicit only; **`auto`** does not infer S3) | Models stored in S3-compatible storage | **`type: Opaque`**, labels **`opendatahub.io/dashboard`** + **`opendatahub.io/managed`**, annotations **`opendatahub.io/connection-type: s3`**, **`…-protocol: s3`**, **`…-ref: s3`**, **`data`** for **`AWS_S3_*`** / **`AWS_ACCESS_KEY_ID`** / **`AWS_SECRET_ACCESS_KEY`** (base64), optional **`AWS_DEFAULT_REGION`**. Set **`model.connection.s3.path`** for **`opendatahub.io/connection-path`** on the serving CR; **`model.uri`** may be omitted when the operator injects storage (see RHOAI *Using the connections API*). |

Connection Secrets also set **`openshift.io/description`** and **`openshift.io/display-name`** to **`name`**, matching typical dashboard-created resources.

### Hugging Face token

Gated or private **`hf://`** checkpoints need a token. Put it in **`.hf_token`** (git-ignored; see **`.hf_token.example`**) or export **`HF_TOKEN`**. The chart creates **`hf-secret`** and mounts **`HF_TOKEN`** only when **`model.uri`** starts with **`hf://`** and **`hfToken`** is non-empty at render time ([KServe / Hugging Face storage](https://kserve.github.io/website/docs/model-serving/storage/providers/hf)). Public **`hf://`** models in this repo (for example Nomic) can deploy without a token.

> [!TIP]
> **`oci://`** ModelCars (Qwen3-8B, GPT-OSS 20B, Granite 4.0 H Tiny here) do not use Hugging Face download auth.

### Generative models

| Model | Deploy | Test when ready |
|-------|--------|-----------------|
| Qwen3-8B-FP8-dynamic (OCI, 1×GPU) | `./deploy-mode.sh chart/values-qwen3-8b-fp8-dynamic.yaml` | `./tests/test-generative.sh model-qwen qwen3-8b` |
| GPT-OSS 20B (OCI, 1×GPU) | `./deploy-mode.sh chart/values-gpt-oss-20b.yaml` | `./tests/test-generative.sh model-gpt-oss gpt-oss-20b` |
| Granite 4.0 H Tiny FP8 (OCI, 1×GPU) | `./deploy-mode.sh chart/values-granite-4-0-h-tiny.yaml` | `./tests/test-generative.sh model-granite granite-4-0-h-tiny` |
| Llama 3.1 70B (4×GPU, gated **`hf://`**) | `./deploy-mode.sh chart/values-llama-3.1-70b.yaml --set-file hfToken=.hf_token` | `./tests/test-generative.sh model-llama llama-3-1-70b` |

**TinyLlama 1B** (CPU **`mainContainer`**, no TinyLlama GPU overlay in this chart): **`values-tinyllama-1b-cpu.yaml`** uses **`router.gateway: {}`** (llm-d + Route). **`values-tinyllama-1b-maas.yaml`** targets namespace **`model-maas`** and needs real **`routerGatewayRefs`** (Models-as-a-Service **Managed** on the cluster; in **rhoai-gitops** enable **`modelsAsService.enabled`** in **`rhoai-installation-chart/values.yaml`** when you use Gateway refs). Deploy CPU path: `./deploy-mode.sh chart/values-tinyllama-1b-cpu.yaml` → `./tests/test-generative.sh model-tinyllama tinyllama-1b`. MaaS path: use **`./deploy-mode.sh`** with **`--set-json 'routerGatewayRefs=[…]'`** as in the **Deploy** example above → **`./tests/test-generative.sh model-maas tinyllama-1b`**. List gateways with **`oc get gateway.networking.k8s.io -A`**.

If you use [rhoai-maas-gitops](https://github.com/davidseve/rhoai-maas-gitops) **`maas-platform`**, the default gateway name is often **`maas-default-gateway`** in **`openshift-ingress`** when **`gateway.enabled`** is true; ensure **`model-maas`** appears in **`gateway.modelNamespaces`** or routes will not attach.

> [!WARNING]
> Forcing **CPU** on the **platform default** vLLM image (for example only **`VLLM_TARGET_DEVICE=cpu`**) can still hit PyTorch / vLLM CPU worker mismatches on some builds ([vLLM#33675](https://github.com/vllm-project/vllm/issues/33675)). Prefer the TinyLlama CPU or MaaS overlays, or use another GPU overlay as a template for TinyLlama on GPU.

### Predictive models

**DistilBERT** (CPU OpenVINO, TrustyAI monitoring): `./deploy-mode.sh chart/values-distilbert.yaml` → `./tests/test-predictive.sh distilbert`

### Embedding models (Hugging Face + vLLM)

**`LLMInferenceService`** with **`hf://`** URIs and **`--task embedding`**. **Nomic** and **BGE-M3** are **GPU-only** in this repo: **platform vLLM worker**, **`gpu-profile`**, **`extraArgs`** (no **`mainContainer`**). **Nomic** adds **`--trust-remote-code`** for its Hub **`config.json`**. vLLM: [pooling / embedding models](https://docs.vllm.ai/en/latest/models/pooling_models/embed/); cards: [nomic-embed-text-v1](https://huggingface.co/nomic-ai/nomic-embed-text-v1), [bge-m3](https://huggingface.co/BAAI/bge-m3).

| Model | Deploy |
|-------|--------|
| Nomic Embed v1 (GPU) | `./deploy-mode.sh chart/values-nomic-embed-text-v1.yaml` |
| BGE-M3 (GPU; tune resources if needed) | `./deploy-mode.sh chart/values-bge-m3.yaml` |

Call **`/v1/embeddings`** with **`spec.model.name`** (for example **`nomic-ai/nomic-embed-text-v1`**). Nomic’s card suggests **task instruction prefixes** for RAG (**`search_document:`** / **`search_query:`**); the chart does not enforce them. Copy **`values-nomic-embed-text-v1.yaml`** or **`values-bge-m3.yaml`** if you want another embedding namespace with different **`resources`**.

### Guardrails — LlamaGuard (Hugging Face + vLLM)

**LlamaGuard 7B** ([`meta-llama/LlamaGuard-7b`](https://huggingface.co/meta-llama/LlamaGuard-7b)): gated; accept Meta’s terms, then **`./deploy-mode.sh chart/values-llamaguard-7b.yaml --set-file hfToken=.hf_token`**. The overlay sets **`dashboard.genaiUseCase: moderation`**; if your OpenShift AI build rejects it, use **`chat`** in **`chart/values-llamaguard-7b.yaml`**. Call **`/v1/chat/completions`** on **`status.url`**. See for example [NeMo Guardrails — Llama Guard with vLLM](https://docs.nvidia.com/nemo/guardrails/latest/user-guides/advanced/llama-guard-deployment.html). **Llama Guard 4** options are commented in the same values file.

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
