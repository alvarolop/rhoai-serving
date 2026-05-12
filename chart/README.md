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
- **Guardrails**: `values-llamaguard-7b.yaml` (gated HuggingFace; requires `hfToken`)

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

All models use a unified `scaling` configuration with four modes:

```yaml
scaling:
  mode: fixed  # "fixed", "hpa" (predictive only), "keda" (predictive only), or "wva" (generative only, not yet available)
  replicas: 1  # Used when mode: fixed
```

### Generative Models (LLMInferenceService)

**Fixed scaling** (default and currently only supported option):
```yaml
scaling:
  mode: fixed
  replicas: 1
```

**WVA autoscaling** (coming soon): Will use `mode: wva` for inference-aware autoscaling with Workload Variant Autoscaler.

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

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| auth | object | `{"enabled":true}` | Authentication configuration via Red Hat Connectivity Link (Kuadrant/Authorino) |
| auth.enabled | bool | `true` | Enable authentication for the inference service |
| chatTemplate | object | `{"enabled":false,"template":""}` | Custom chat template for generative models (vLLM). Use when model lacks built-in template. |
| chatTemplate.enabled | bool | `false` | Enable custom chat template via ConfigMap |
| dashboard | object | `{"genaiUseCase":"chat","modelType":"generative"}` | OpenShift AI dashboard annotations (generative models only) |
| dashboard.genaiUseCase | string | `"chat"` | Gen AI use case type: "chat", "embedding", "moderation" |
| dashboard.modelType | string | `"generative"` | Model type annotation |
| guardrails | object | `{"enabled":false,"nemo":{"image":"","modelToken":"","modelUrl":"","resources":{"limits":{"cpu":"2","memory":"4Gi"},"requests":{"cpu":"500m","memory":"1Gi"}}},"type":"nemo"}` | Guardrails for content moderation and safety |
| guardrails.enabled | bool | `false` | Enable guardrails integration |
| guardrails.nemo | object | `{"image":"","modelToken":"","modelUrl":"","resources":{"limits":{"cpu":"2","memory":"4Gi"},"requests":{"cpu":"500m","memory":"1Gi"}}}` | NeMo Guardrails configuration (only used when type is "nemo") |
| guardrails.nemo.image | string | quay.io/rhoai/nemo-guardrails:latest | Container image for NeMo Guardrails server |
| guardrails.nemo.modelToken | string | `""` | API token for model authentication (if required) |
| guardrails.nemo.modelUrl | string | `""` | LLM model endpoint URL (e.g., https://model-name-predictor.namespace.svc.cluster.local:8443/v1) |
| guardrails.nemo.resources | object | `{"limits":{"cpu":"2","memory":"4Gi"},"requests":{"cpu":"500m","memory":"1Gi"}}` | Container resource limits and requests |
| guardrails.type | string | `"nemo"` | Guardrails type: "nemo" (NVIDIA NeMo Guardrails) |
| hfToken | string | "" (pass via --set-file hfToken=.hf_token) | Hugging Face token for gated/private models. Chart creates hf-secret when model.uri starts with hf:// and this is non-empty. |
| kueue | object | `{"localQueueName":"default"}` | Kueue LocalQueue configuration |
| kueue.localQueueName | string | `"default"` | LocalQueue name used as label kueue.x-k8s.io/queue-name on serving CRs. Must match a LocalQueue in the model namespace. |
| mainContainer | object | `{"args":[],"command":[],"env":[],"extraArgs":[],"image":"","livenessProbe":{},"readinessProbe":{},"startupProbe":{}}` | Main container configuration for LLMInferenceService/InferenceService pods |
| mainContainer.args | list | `[]` | Container args override |
| mainContainer.command | list | `[]` | Container command override |
| mainContainer.env | list | `[]` | Extra environment variables in standard Kubernetes env var format |
| mainContainer.extraArgs | list | `[]` | Extra runtime arguments. For generative models, joined into VLLM_ADDITIONAL_ARGS env var. For predictive models, appended as container args. |
| mainContainer.image | string | `""` | Container image (leave empty to use OpenShift AI default vLLM or OpenVINO image) |
| mainContainer.livenessProbe | object | `{}` | Liveness probe configuration |
| mainContainer.readinessProbe | object | `{}` | Readiness probe configuration |
| mainContainer.startupProbe | object | `{}` | Startup probe configuration (useful for large models with slow load times >2min) |
| model | object | `{"connection":{"oci":{"dockerconfigjson":"","host":""},"protocol":"auto","s3":{"accessKeyId":"","bucket":"","endpoint":"","objectBucketClaim":"","path":"","region":"","secretAccessKey":""}},"name":"","uri":""}` | Model source configuration (KServe/OpenShift AI storage URI). Supported schemes: hf://, s3://, pvc://, oci:// |
| model.connection | object | `{"oci":{"dockerconfigjson":"","host":""},"protocol":"auto","s3":{"accessKeyId":"","bucket":"","endpoint":"","objectBucketClaim":"","path":"","region":"","secretAccessKey":""}}` | Dashboard connection Secret configuration |
| model.connection.oci | object | `{"dockerconfigjson":"","host":""}` | OCI registry connection settings |
| model.connection.oci.dockerconfigjson | string | `""` | Docker config JSON for private registries (base64 encoded). Leave empty for public registries. |
| model.connection.oci.host | string | `""` | Legacy OCI host field (deprecated, use model.uri) |
| model.connection.protocol | string | `"auto"` | Connection protocol: "auto", "uri", "oci", or "s3". Auto detects from model.uri prefix. |
| model.connection.s3 | object | `{"accessKeyId":"","bucket":"","endpoint":"","objectBucketClaim":"","path":"","region":"","secretAccessKey":""}` | S3-compatible storage configuration |
| model.connection.s3.accessKeyId | string | `""` | S3 access key ID |
| model.connection.s3.bucket | string | `""` | S3 bucket name |
| model.connection.s3.endpoint | string | `""` | S3 endpoint URL (e.g., http://minio.minio.svc.cluster.local:9000) |
| model.connection.s3.objectBucketClaim | string | `""` | OpenShift Data Foundation ObjectBucketClaim name. When set, credentials are read from ODF-generated Secret/ConfigMap instead of manual fields above. |
| model.connection.s3.path | string | `""` | Object prefix/path inside the bucket (opendatahub.io/connection-path annotation) |
| model.connection.s3.region | string | `""` | S3 region |
| model.connection.s3.secretAccessKey | string | `""` | S3 secret access key |
| model.name | string | `""` | Model name for serving requests |
| model.uri | string | `""` | Model URI (e.g., hf://RedHatAI/Qwen3-8B-FP8-dynamic, oci://registry.redhat.io/rhelai1/modelcar-qwen3-8b-fp8-dynamic:1.5) |
| name | string | `"model-server"` | Resource identity name for the model serving deployment |
| namespace | object | `{"create":true,"description":"","displayName":"","kueueManaged":true,"name":"model-serving"}` | Target namespace configuration for all chart resources |
| namespace.create | bool | `true` | Create the namespace if it doesn't exist |
| namespace.description | string | `""` | OpenShift console description annotation (optional) |
| namespace.displayName | string | `""` | OpenShift console display name (defaults to .name if empty) |
| namespace.kueueManaged | bool | `true` | Enable Kueue management label for queue enforcement (Red Hat OpenShift AI workload scheduling) |
| namespace.name | string | `"model-serving"` | Namespace name |
| resources | object | {} (set in model-specific values files) | Container resource limits and requests. Override in values-<model>.yaml files per model requirements. |
| routerGatewayRefs | list | [] | Gateway API refs for spec.router.gateway. Default empty for standard llm-d + Route. Set for MaaS deployments. |
| runtime | object | `{"displayName":"OpenVINO Model Server","image":"quay.io/opendatahub/openvino_model_server:stable","modelFormat":{"name":"openvino_ir","version":"opset13"},"version":"v2025.4"}` | Predictive runtime configuration (only used when serving.type is "predictive") |
| runtime.displayName | string | `"OpenVINO Model Server"` | ServingRuntime display name |
| runtime.image | string | `"quay.io/opendatahub/openvino_model_server:stable"` | Runtime container image |
| runtime.modelFormat | object | `{"name":"openvino_ir","version":"opset13"}` | Model format specification |
| runtime.modelFormat.name | string | `"openvino_ir"` | Model format name |
| runtime.modelFormat.version | string | `"opset13"` | Model format version |
| runtime.version | string | `"v2025.4"` | Runtime version |
| scaling | object | `{"hpa":{"maxReplicas":5,"minReplicas":1,"scaleMetric":"cpu","scaleTarget":80},"keda":{"maxReplicas":5,"minReplicas":1,"pollingInterval":5,"prometheus":{"authModes":"bearer","query":"","serverAddress":"https://thanos-querier.openshift-monitoring.svc.cluster.local:9092","threshold":2}},"mode":"fixed","replicas":1}` | Scaling configuration for model serving workloads |
| scaling.hpa | object | `{"maxReplicas":5,"minReplicas":1,"scaleMetric":"cpu","scaleTarget":80}` | HPA autoscaling configuration (only used when mode is "hpa" for predictive models). Uses standard Kubernetes HPA with CPU/memory metrics. |
| scaling.hpa.maxReplicas | int | `5` | Maximum number of replicas for autoscaling |
| scaling.hpa.minReplicas | int | `1` | Minimum number of replicas for autoscaling |
| scaling.hpa.scaleMetric | string | `"cpu"` | Scaling metric type (cpu or memory) |
| scaling.hpa.scaleTarget | int | `80` | Target value for the metric (e.g., 80 for 80% CPU utilization) |
| scaling.keda | object | `{"maxReplicas":5,"minReplicas":1,"pollingInterval":5,"prometheus":{"authModes":"bearer","query":"","serverAddress":"https://thanos-querier.openshift-monitoring.svc.cluster.local:9092","threshold":2}}` | KEDA autoscaling configuration (only used when mode is "keda" for predictive models). Requires KEDA operator installed. |
| scaling.keda.maxReplicas | int | `5` | Maximum number of replicas for autoscaling |
| scaling.keda.minReplicas | int | `1` | Minimum number of replicas for autoscaling |
| scaling.keda.pollingInterval | int | `5` | Polling interval in seconds for checking metrics |
| scaling.keda.prometheus | object | `{"authModes":"bearer","query":"","serverAddress":"https://thanos-querier.openshift-monitoring.svc.cluster.local:9092","threshold":2}` | Prometheus trigger configuration |
| scaling.keda.prometheus.authModes | string | `"bearer"` | Authentication mode for Prometheus (bearer token from ServiceAccount) |
| scaling.keda.prometheus.query | string | sum(ovms_current_requests{namespace="NAMESPACE", pod=~"NAME-predictor.*"}) | PromQL query for scaling metric. Default uses ovms_current_requests for OpenVINO models. |
| scaling.keda.prometheus.serverAddress | string | https://thanos-querier.openshift-monitoring.svc.cluster.local:9092 | Prometheus server address (default: Thanos Querier in openshift-monitoring) |
| scaling.keda.prometheus.threshold | int | `2` | Threshold value that triggers scaling (number of concurrent requests) |
| scaling.mode | string | `"fixed"` | Scaling mode: "fixed" (static replicas), "hpa" (predictive models CPU/memory HPA), "keda" (predictive models custom metrics), "wva" (generative models - not yet available) |
| scaling.replicas | int | `1` | Number of replicas when mode is "fixed" |
| serving | object | `{"gpuPodTolerations":true,"hardwareProfile":{"name":"gpu-profile","namespace":"redhat-ods-applications"},"type":"generative"}` | Model serving configuration. Determines whether to deploy generative (LLMInferenceService) or predictive (InferenceService) models. |
| serving.gpuPodTolerations | bool | `true` | Enable GPU pod tolerations when resources request nvidia.com/gpu. Matches Kueue ResourceFlavor tolerations. |
| serving.hardwareProfile | object | `{"name":"gpu-profile","namespace":"redhat-ods-applications"}` | OpenShift AI HardwareProfile reference |
| serving.hardwareProfile.name | string | `"gpu-profile"` | HardwareProfile name (cpu-profile for CPU-only, gpu-profile for GPU models) |
| serving.hardwareProfile.namespace | string | redhat-ods-applications | HardwareProfile namespace |
| serving.type | string | `"generative"` | Serving type: "generative" for vLLM-based LLMs, "predictive" for OpenVINO/ONNX runtimes |
| trustyai | object | `{"enabled":false}` | TrustyAI monitoring for bias and data drift detection |
| trustyai.enabled | bool | `false` | Enable TrustyAI service deployment |

## Examples

### Deploy Qwen3-8B (OCI ModelCar, Static Scaling)

```bash
helm template qwen chart/ \
  -f chart/values.yaml \
  -f chart/values-qwen3-8b-fp8-dynamic.yaml | oc apply -f -
```

### Deploy BGE-M3 Embeddings (HuggingFace, GPU)

```bash
helm template bge-m3 chart/ \
  -f chart/values.yaml \
  -f chart/values-bge-m3.yaml | oc apply -f -
```

### Deploy LlamaGuard-7B (Gated HF Model)

```bash
helm template llamaguard chart/ \
  -f chart/values.yaml \
  -f chart/values-llamaguard-7b.yaml \
  --set hfToken=$(cat .hf_token) | oc apply -f -
```

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
