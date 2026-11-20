# rhoai-serving

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 1.0](https://img.shields.io/badge/AppVersion-1.0-informational?style=flat-square)

Production-ready Helm chart for deploying Predictive and Generative AI models on Red Hat OpenShift AI using KServe Raw deployment mode

**Homepage:** <https://github.com/alvarolop/rhoai-serving>

## Overview

This Helm chart provides production-ready deployments for **Predictive** and **Generative AI** models on OpenShift using Red Hat OpenShift AI (RHOAI). The chart uses KServe in **Raw deployment mode** for maximum flexibility.

### Supported Scenarios

- **Predictive model serving** - Using OpenVINO runtime (`serving.type: predictive`)
- **Generative model serving** - Using vLLM runtime for single GPU deployments (`serving.type: generative`)
- **Embeddings model serving** - Using vLLM with pooling support
- **Autoscaling** - HPA/KEDA-based dynamic scaling with inference-aware metrics

### Two-Layer Values Architecture

1. **`values.yaml`** - Shared defaults and schema reference (generative models, GPU by default)
2. **`values-<model>.yaml`** - Model-specific overrides (name, namespace, URI, resources, connection settings)

**Usage:**
```bash
helm template <release> chart/ \
  -f chart/values.yaml \
  -f chart/values-<model>.yaml
```

### Example Values Files

- **Generative (GPU)**: `values-qwen3-8b-fp8-dynamic.yaml`, `values-gpt-oss-20b.yaml`
- **Embeddings (GPU)**: `values-bge-m3.yaml`, `values-nomic-embed-text-v2-moe-gpu.yaml`
- **Predictive (CPU)**: `values-distilbert.yaml` (includes KEDA autoscaling configuration example)
- **Guardrails**: `values-granite-guardian-4.1-8b.yaml` (ModelCar on Quay)

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| Alvaro Lopez Medina | <alopezme@redhat.com> |  |

## Source Code

* <https://github.com/alvarolop/rhoai-serving>
* <https://kserve.github.io/website>
* <https://docs.redhat.com/en/documentation/red_hat_openshift_ai_self-managed>

## Prerequisites

Required cluster components (can be installed via [rhoai-gitops](https://github.com/redhat-na-ssa/rhoai-gitops)):

- OpenShift Container Platform 4.20+
- OpenShift AI (RHOAI) with dependencies:
  - OpenShift Pipelines
  - Kueue (Red Hat build)
  - Node Feature Discovery
  - NVIDIA GPU Operator (for GPU models)
  - Authorino (for authentication)

## Model Source Options

The chart supports multiple methods for loading models:

- **OCI Registry (ModelCar)** - Pull models from OCI-compliant registries (`oci://registry.redhat.io/...`)
- **S3-compatible storage** - Load from S3 buckets (AWS S3, MinIO, Ceph) via `s3://` URI
- **PVC (Persistent Volume Claims)** - Use models on persistent volumes via `pvc://` URI
- **HuggingFace Hub** - Pull directly from HF Hub via `hf://` URI (use `hfToken` for gated models)

### S3 Configuration

**Option 1: Manual S3 credentials** - Set `model.connection.s3.endpoint`, `bucket`, `accessKeyId`, `secretAccessKey`

**Option 2: OpenShift Data Foundation ObjectBucketClaim** - Set `model.connection.s3.objectBucketClaim` to auto-read ODF-generated credentials

See `values-example-minio-s3-tinyllama.yaml` and `values-example-odf-obc-s3.yaml` for examples.

## Scaling

### Configuration Structure

All models use a unified `scaling` configuration with three modes:

```yaml
scaling:
  mode: fixed  # "fixed", "hpa" (predictive only) or "keda" (predictive only)
  replicas: 1  # Used when mode: fixed
```

### Generative Models (LLMInferenceService)

**Fixed scaling** (the only option the chart renders for generative models):
```yaml
scaling:
  mode: fixed
  replicas: 1
```

**WVA autoscaling** (Technology Preview in RHOAI 3.5): the Workload Variant Autoscaler scales on KV cache usage and queue depth and is configured in the `LLMInferenceService` itself. The chart does not render it yet.

### Predictive Models (InferenceService)

Predictive models support three scaling modes:

#### **Option 1: Fixed scaling** (default)
Static replica count, no autoscaling:
```yaml
scaling:
  mode: fixed
  replicas: 1
```

#### **Option 2: HPA autoscaling** (native Kubernetes)
Standard Kubernetes HPA based on CPU/memory metrics. KServe creates the HPA automatically:
```yaml
scaling:
  mode: hpa
  hpa:
    minReplicas: 1
    maxReplicas: 5
    scaleMetric: cpu      # cpu or memory
    scaleTarget: 80       # Target value (e.g., 80 for 80% CPU utilization)
```

When `mode: hpa`:
- KServe creates a standard Kubernetes HPA automatically
- Scales based on CPU utilization (default) or memory
- `scaleMetric` specifies the metric type (cpu or memory)
- `scaleTarget` specifies the target value (e.g., 80 for 80% utilization)
- No additional operators required

#### **Option 3: KEDA autoscaling** (custom metrics)
KEDA-based autoscaling with custom Prometheus queries. Requires KEDA operator installed:
```yaml
scaling:
  mode: keda
  keda:
    minReplicas: 1
    maxReplicas: 5
    pollingInterval: 5
    prometheus:
      serverAddress: https://thanos-querier.openshift-monitoring.svc.cluster.local:9092
      threshold: "2"
      authModes: "bearer"
```

When `mode: keda`:
- Sets `serving.kserve.io/autoscalerClass: external` to disable default KServe HPA
- Creates a `ScaledObject` that monitors `ovms_current_requests` metric (OpenVINO current requests)
- Scales between min/max replicas when concurrent requests exceed threshold
- Uses Thanos Querier for Prometheus metrics access with bearer token auth
- Requires KEDA operator installed cluster-wide

See `values-distilbert.yaml` for all configuration examples (HPA and KEDA blocks are commented by default).

#### **Choosing Between HPA and KEDA**

**Use HPA when:**
- You want simple CPU or memory-based autoscaling
- You don't need custom metrics from Prometheus
- You want native Kubernetes functionality without additional operators
- Resource-based scaling is sufficient for your workload

**Use KEDA when:**
- You need custom Prometheus metrics (e.g., `ovms_current_requests`)
- You want to scale based on external systems (queues, databases, etc.)
- You need more sophisticated scaling triggers
- You already have KEDA deployed in your cluster

## Distributed Multi-GPU Parallelism

For large models that require multiple GPUs, configure tensor and/or data parallelism in your values file:

```yaml
# Tensor Parallelism: Split model weights across 4 GPUs (single node)
parallelism:
  tensor: 4

# Combined Tensor + Data Parallelism: 8 total replicas with 4-way tensor parallelism
parallelism:
  tensor: 4     # Split model across 4 GPUs
  data: 8       # Total replica groups
  dataLocal: 4  # Replicas per node before scaling to additional nodes
```

**Examples:**
- **Llama 3.3 70B** (`values-llama-3.3-70b.yaml`): `tensor: 2` across the 2 GPUs of the `gpu-xl-x2` claim template
- **Future multi-node deployments**: Combine `tensor`, `data`, and `dataLocal` for distributed serving

Only applies to generative models (`LLMInferenceService`). Predictive models use replica-based scaling instead.

## GPUs with Dynamic Resource Allocation (DRA)

**TL;DR:** `serving.dra.enabled` (default `true`) requests the GPU through a platform-defined `ResourceClaimTemplate` named in `serving.dra.claimTemplate` (`gpu-s-x1`, `gpu-m-x1`, `gpu-l-x1`, `gpu-xl-x1`, `gpu-xl-x2`). The chart creates no templates. CPU models never get a claim.

```bash
# DRA (default)
helm template <release> chart/ -f chart/values.yaml -f chart/values-<model>.yaml | oc apply -f -

# Device plugin (clusters without the NVIDIA DRA driver)
helm template <release> chart/ -f chart/values.yaml -f chart/values-<model>.yaml --set serving.dra.enabled=false | oc apply -f -
```

Details and diagrams in [docs/010-dra-gpu-claims.md](../docs/010-dra-gpu-claims.md).

## Health Probes

For large models with slow startup times (>2min), configure health probes to prevent premature restarts:

```yaml
mainContainer:
  startupProbe:
    httpGet:
      path: /health
      port: 8000
      scheme: HTTPS
    initialDelaySeconds: 30
    periodSeconds: 10
    failureThreshold: 30  # 5min max startup
  livenessProbe:
    httpGet:
      path: /health
      port: 8000
      scheme: HTTPS
    periodSeconds: 30
    failureThreshold: 2
  readinessProbe:
    httpGet:
      path: /health
      port: 8000
      scheme: HTTPS
    periodSeconds: 10
    failureThreshold: 3
```

See `values-gpt-oss-20b.yaml` for an example.

## TrustyAI Monitoring

Enable TrustyAI for bias and data drift detection:

```yaml
trustyai:
  enabled: true
```

Deploys a TrustyAIService CR and required CA bundle ConfigMap. See `values-distilbert.yaml` for a predictive model example.

## Values

### Other Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| name | string | `"model-server"` | Resource identity name for the model serving deployment |

### Namespace Configuration

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| namespace | object | `{"name":"models-as-a-service"}` | Target namespace for all chart resources. The namespace is NOT created by this chart: it is owned by the platform (rhoai-gitops creates it, labels it for Kueue and creates the LocalQueues and GPU claim templates). |
| namespace.name | string | `"models-as-a-service"` | Namespace name |

### Kueue Configuration

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| kueue | object | `{"localQueue":"","priorityClass":""}` | Kueue queues (rhoai-gitops "reserved-spot"). The ClusterQueues, LocalQueues and WorkloadPriorityClasses are created by rhoai-gitops, not by this chart. |
| kueue.localQueue | string | `"" (derived)` | LocalQueue for the workload label. Empty = derive from serving.hardwareProfile.name (gpu-profile: serving-lq, gpu-batch-profile: batch-lq, otherwise default). Must match the HardwareProfile spec.scheduling.kueue.localQueueName. |
| kueue.priorityClass | string | `"" (derived)` | WorkloadPriorityClass for the workload label kueue.x-k8s.io/priority-class (orders models inside serving-cq). Empty = derive from serving.hardwareProfile.name (gpu-profile: model-critical, gpu-batch-profile: batch-nightly, otherwise no label). Other classes: model-standard, batch-interactive. |

### Serving Configuration

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| serving | object | `{...}` (see sub-keys) | Model serving configuration. Determines whether to deploy generative (LLMInferenceService) or predictive (InferenceService) models. |
| serving.dra | object | `{"enabled":true,"claimTemplate":"","hardwareProfile":"gpu-dra-profile"}` | GPU through Dynamic Resource Allocation (DRA) instead of the NVIDIA device plugin: the pod references a ResourceClaimTemplate (`resourceClaims` + `resources.claims`) instead of `nvidia.com/gpu`. The templates are defined by the platform team (rhoai-gitops `06-dra`), not by this chart. CPU models never get a claim. See docs/010-dra-gpu-claims.md. |
| serving.dra.claimTemplate | string | `""` | Platform-defined ResourceClaimTemplate in the model namespace; required for GPU models when DRA is on. Sizes: `gpu-s-x1` (small, embeddings), `gpu-m-x1` (L4-class), `gpu-l-x1` (1x H100), `gpu-xl-x1` (1 GPU with 140 Gi or more), `gpu-xl-x2` (2 GPUs, needs `parallelism.tensor: 2`). The GPU count comes from the template. |
| serving.dra.enabled | bool | `true` | Use a ResourceClaim (true) or `nvidia.com/gpu` limits (false). Set false on clusters without the NVIDIA DRA driver. |
| serving.dra.hardwareProfile | string | `"gpu-dra-profile"` | HardwareProfile written in the annotation of DRA models whose profile is `gpu-profile`. It must not carry an `nvidia.com/gpu` identifier (the webhook would add it on top of the claim and Kueue would count 2 GPUs). |
| serving.hardwareProfile | object | `{"name":"gpu-profile","namespace":"redhat-ods-applications"}` | OpenShift AI HardwareProfile reference |
| serving.hardwareProfile.name | string | `"gpu-profile"` | HardwareProfile name (cpu-profile for CPU-only, gpu-profile for GPU models) |
| serving.hardwareProfile.namespace | string | `redhat-ods-applications` | HardwareProfile namespace |
| serving.maas | object | `{"enabled":true}` | MaaS (Models-as-a-Service) catalog integration. Creates MaaSModelRef CR using model.displayName, model.description and model.metadata.useCase. |
| serving.maas.enabled | bool | `true` | Enable MaaSModelRef creation for MaaS catalog (generative models only: MaaS supports LLMInferenceService, not InferenceService) |
| serving.router | object | `{"route":{"requestTimeout":""},"scheduler":{"endpointPickerConfig":{}}}` | Router configuration for intelligent routing and HTTPRoute settings |
| serving.router.route | object | `{"requestTimeout":""}` | HTTPRoute configuration for request timeouts and URL rewriting |
| serving.router.route.requestTimeout | string | `""` | Request timeout for long-running inference (e.g., "300s", "5m"). Leave empty for default Gateway timeout. |
| serving.router.scheduler | object | `{"endpointPickerConfig":{}}` | Scheduler configuration (llm-d EPP). Always enabled in RHOAI 3.4+ for intelligent routing. |
| serving.router.scheduler.endpointPickerConfig | object | `{} (uses default EPP configuration)` | Custom EndpointPickerConfig for advanced scheduler tuning. Rendered into a ConfigMap (<name>-epp-config) and referenced via router.scheduler.config.ref. Leave empty for defaults (queue-scorer, kv-cache-utilization-scorer, prefix-cache-scorer, no-hit-lru-scorer with weights 2:2:3:2). |
| serving.routerGatewayRefs | list | `MaaS gateway (maas-default-gateway / openshift-ingress)` | Gateway API refs for spec.router.gateway. Default: the MaaS gateway (maas-default-gateway in openshift-ingress), so models are published through Models-as-a-Service. The model namespace must be allowed by the gateway. To use the standard llm-d gateway (openshift-ai-inference) instead, set `[]`. |
| serving.type | string | `"generative"` | Serving type: "generative" for vLLM-based LLMs, "predictive" for OpenVINO/ONNX runtimes |

### Scaling Configuration

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| scaling | object | `{...}` (see sub-keys) | Scaling configuration for model serving workloads |
| scaling.hpa | object | `{"minReplicas":1,"maxReplicas":5,"scaleMetric":"cpu","scaleTarget":80}` | HPA autoscaling configuration (only used when mode is "hpa" for predictive models). Uses standard Kubernetes HPA with CPU/memory metrics. |
| scaling.hpa.maxReplicas | int | `5` | Maximum number of replicas for autoscaling |
| scaling.hpa.minReplicas | int | `1` | Minimum number of replicas for autoscaling |
| scaling.hpa.scaleMetric | string | `"cpu"` | Scaling metric type (cpu or memory) |
| scaling.hpa.scaleTarget | int | `80` | Target value for the metric (e.g., 80 for 80% CPU utilization) |
| scaling.keda | object | `{...}` (see sub-keys) | KEDA autoscaling configuration (only used when mode is "keda" for predictive models). Requires KEDA operator installed. |
| scaling.keda.maxReplicas | int | `5` | Maximum number of replicas for autoscaling |
| scaling.keda.minReplicas | int | `1` | Minimum number of replicas for autoscaling |
| scaling.keda.pollingInterval | int | `5` | Polling interval in seconds for checking metrics |
| scaling.keda.prometheus | object | `{...}` (see sub-keys) | Prometheus trigger configuration |
| scaling.keda.prometheus.authModes | string | `"bearer"` | Authentication mode for Prometheus (bearer token from ServiceAccount) |
| scaling.keda.prometheus.query | string | `sum(ovms_current_requests{namespace="NAMESPACE", pod=~"NAME-predictor.*"})` | PromQL query for scaling metric. Default uses ovms_current_requests for OpenVINO models. |
| scaling.keda.prometheus.serverAddress | string | `https://thanos-querier.openshift-monitoring.svc.cluster.local:9092` | Prometheus server address (default: Thanos Querier in openshift-monitoring) |
| scaling.keda.prometheus.threshold | int | `2` | Threshold value that triggers scaling (number of concurrent requests) |
| scaling.mode | string | `"fixed"` | Scaling mode: "fixed" (static replicas), "hpa" (predictive models CPU/memory HPA), "keda" (predictive models custom metrics) |
| scaling.replicas | int | `1` | Number of replicas when mode is "fixed" |

### Model Configuration

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| model | object | `{...}` (see sub-keys) | Model source configuration (KServe/OpenShift AI storage URI). Supported schemes: hf://, s3://, pvc://, oci:// |
| model.description | string | `""` | Description in the MaaS catalog (MaaSModelRef). Defaults to "Serving model <name>" if empty. |
| model.displayName | string | `""` | Display name in the MaaS catalog (MaaSModelRef). Defaults to "Model - <name>" if empty. |
| model.maxModelLen | string | `""` | Maximum model sequence length (context window). Optional - only set when using --max-model-len vLLM arg or for MaaSModelRef annotation. |
| model.metadata | object | `{"useCase":"chat","type":"generative"}` | Model metadata annotations for OpenShift AI dashboard and MaaS catalog |
| model.metadata.type | string | `"generative"` | Model type: "generative", "predictive" |
| model.metadata.useCase | string | `"chat"` | Use case type: "chat", "embedding", "moderation" |
| model.name | string | `""` | Model name for serving requests |
| model.oci | object | `{"dockerconfigjson":""}` | OCI registry connection settings (only used when uri starts with oci://) |
| model.oci.dockerconfigjson | string | `""` | Docker config JSON for private registries (base64 encoded). Leave empty for public registries. |
| model.s3 | object | `{...}` (see sub-keys) | S3-compatible storage configuration (only used when uri starts with s3://) |
| model.s3.accessKeyId | string | `""` | S3 access key ID |
| model.s3.bucket | string | `""` | S3 bucket name |
| model.s3.endpoint | string | `""` | S3 endpoint URL (e.g., http://minio.minio.svc.cluster.local:9000) |
| model.s3.objectBucketClaim | string | `""` | OpenShift Data Foundation ObjectBucketClaim name. When set, credentials are read from ODF-generated Secret/ConfigMap instead of manual fields above. |
| model.s3.path | string | `""` | Object prefix/path inside the bucket (opendatahub.io/connection-path annotation) |
| model.s3.region | string | `""` | S3 region |
| model.s3.secretAccessKey | string | `""` | S3 secret access key |
| model.uri | string | `""` | Model URI (e.g., hf://RedHatAI/Qwen3-8B-FP8-dynamic, oci://registry.redhat.io/rhelai1/modelcar-qwen3-8b-fp8-dynamic:1.5) |

### Authentication and Secrets

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| auth | object | `{"enabled":true}` | Authentication configuration via Red Hat Connectivity Link (Kuadrant/Authorino) |
| auth.enabled | bool | `true` | Enable authentication for the inference service |
| hfToken | string | `"" (pass via --set-file hfToken=.hf_token)` | Hugging Face token for gated/private models. Chart creates hf-secret when model.uri starts with hf:// and this is non-empty. |

### Chat Template Configuration

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| chatTemplate | object | `{"enabled":false,"template":""}` | Custom chat template for generative models (vLLM). Use when model lacks built-in template. |
| chatTemplate.enabled | bool | `false` | Enable custom chat template via ConfigMap |
| chatTemplate.template | string | `"" (provide template in model-specific values file)` | Jinja2 template content. Mounted at /etc/vllm/template.jinja and passed to vLLM via --chat-template |

### TrustyAI Configuration

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| trustyai | object | `{"enabled":false}` | TrustyAI monitoring for bias and data drift detection |
| trustyai.enabled | bool | `false` | Enable TrustyAI service deployment |

### Guardrails Configuration

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| guardrails | object | `{...}` (see sub-keys) | Guardrails for content moderation and safety |
| guardrails.config | string | `Jailbreak + script blocking + PII detection` | NeMo Guardrails config.yaml content. This controls which guardrails are active. The model connection (openai_api_base, model_name) is auto-injected by the template. Default configuration includes three core guardrails: 1. Jailbreak detection (keyword-based) 2. Malicious script blocking 3. PII detection (Presidio) Override in model-specific values files to customize entities, thresholds, or disable flows. |
| guardrails.enabled | bool | `false` | Enable NeMo Guardrails integration |
| guardrails.guardLlm | object | `{"enabled":false,"url":"","modelName":"","name":"","namespace":"","token":""}` | Guard LLM Configuration for self-check flows Red Hat OpenShift AI supports using separate models for self-check guardrails (type: self_check_input, self_check_output) This enables smaller, faster models as guardrail judges while reserving larger models for inference |
| guardrails.guardLlm.enabled | bool | `false` | Enable guard LLM for self-check flows |
| guardrails.guardLlm.modelName | string | `""` | Guard model name (must match model.name in the guard model's deployment) |
| guardrails.guardLlm.name | string | `""` | Guard model deployment name (used for URL generation if url is empty) |
| guardrails.guardLlm.namespace | string | `""` | Guard model namespace (used for URL generation if url is empty) |
| guardrails.guardLlm.token | string | `""` | Guard model ServiceAccount token (pass via --set guardrails.guardLlm.token=$(oc get secret <guard-sa-token> -n <namespace> -o jsonpath='{.data.token}' \| base64 -d)) |
| guardrails.guardLlm.url | string | `""` | Guard model endpoint URL (leave empty to auto-generate from name/namespace) |
| guardrails.modelUrl | string | `""` | LLM model endpoint URL. Leave empty to auto-generate: If routerGatewayRefs exists, uses internal gateway (https://<gateway-svc>/<namespace>/<model>/v1). Otherwise, uses direct workload service (https://<model>-kserve-workload-svc:8000). |

### Parallelism Configuration

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| parallelism | object | `{} (single-replica, no parallelism)` | Multi-node distributed workload parallelism for generative models (LLMInferenceService only). Enables tensor parallelism (TP), data parallelism (DP), and expert parallelism (EP) across multiple GPUs/nodes. Leave empty {} for single-replica workloads. |

### Container Configuration

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| mainContainer | object | `{...}` (see sub-keys) | Main container configuration for LLMInferenceService/InferenceService pods |
| mainContainer.args | list | `[]` | Container args override |
| mainContainer.command | list | `[]` | Container command override |
| mainContainer.env | list | `[]` | Extra environment variables in standard Kubernetes env var format |
| mainContainer.extraArgs | list | `[]` | Extra runtime arguments. For generative models, joined into VLLM_ADDITIONAL_ARGS env var. For predictive models, appended as container args. |
| mainContainer.image | string | `""` | Container image (leave empty to use OpenShift AI default vLLM or OpenVINO image) |
| mainContainer.livenessProbe | object | `{}` | Liveness probe configuration |
| mainContainer.readinessProbe | object | `{}` | Readiness probe configuration |
| mainContainer.resources | object | `{} (set in model-specific values files)` | Container resource limits and requests. Override in values-<model>.yaml files per model requirements. |
| mainContainer.startupProbe | object | `{}` | Startup probe configuration (useful for large models with slow load times >2min) |

### Predictive Runtime Configuration

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| runtime | object | `{...}` (see sub-keys) | Predictive runtime configuration (only used when serving.type is "predictive") |
| runtime.displayName | string | `"OpenVINO Model Server"` | ServingRuntime display name |
| runtime.image | string | `"quay.io/opendatahub/openvino_model_server:stable"` | Runtime container image |
| runtime.modelFormat | object | `{"name":"openvino_ir","version":"opset13"}` | Model format specification |
| runtime.modelFormat.name | string | `"openvino_ir"` | Model format name |
| runtime.modelFormat.version | string | `"opset13"` | Model format version |
| runtime.version | string | `"v2026.1.0"` | Runtime version |

## Examples

### Deploy Qwen3-8B (OCI ModelCar, Static Scaling)

```bash
helm template qwen chart/ \
  -f chart/values.yaml \
  -f chart/values-qwen3-8b-fp8-dynamic.yaml | oc apply -f -
```

### Deploy BGE-M3 Embeddings (ModelCar, GPU)

```bash
helm template bge-m3 chart/ \
  -f chart/values.yaml \
  -f chart/values-bge-m3.yaml | oc apply -f -
```

### Deploy Granite Guardian 4.1 (guardrails model)

```bash
helm template granite-guardian chart/ \
  -f chart/values.yaml \
  -f chart/values-granite-guardian-4.1-8b.yaml | oc apply -f -
```

### Gated Hugging Face model

Gated `hf://` models need a token: add `--set-file hfToken=.hf_token` to any command.

### Deploy Predictive Model (OpenVINO, CPU)

```bash
# Fixed scaling (default)
helm template distilbert chart/ \
  -f chart/values.yaml \
  -f chart/values-distilbert.yaml | oc apply -f -

# KEDA autoscaling (uncomment keda block in values-distilbert.yaml and set mode: keda)
helm template distilbert chart/ \
  -f chart/values.yaml \
  -f chart/values-distilbert.yaml | oc apply -f -
```

**Homepage:** <https://github.com/alvarolop/rhoai-serving>

----------------------------------------------
Autogenerated from chart metadata using [helm-docs v1.14.2](https://github.com/norwoodj/helm-docs/releases/v1.14.2)
