# 010 — GPUs through Dynamic Resource Allocation (DRA)

## Context

With the NVIDIA device plugin a model asks for `nvidia.com/gpu` in `resources.limits`. On clusters running the **NVIDIA DRA driver** (OpenShift 4.22 + RHOAI 3.5) there is no device plugin: the pod references a **`ResourceClaimTemplate`** and the scheduler allocates a device from a `ResourceSlice`.

```
GPU hardware
   │  NVIDIA DRA driver (kubelet plugin)
   ▼
ResourceSlice            (per node: productName, architecture, memory, type=gpu|mig, ...)
   │
   ▼
DeviceClass              gpu.nvidia.com / mig.nvidia.com   (created by NVIDIA)
   │
   ▼
ResourceClaimTemplate    gpu-s-x1 / gpu-m-x1 / gpu-l-x1 / gpu-xl-x4   (created by the platform team, rhoai-gitops 06-dra)
   │  one ResourceClaim per pod
   ▼
Pod                      spec.resourceClaims[gpu] + containers[].resources.claims[gpu]   (written by this chart)
```

Kueue 1.5 evaluates the claims. **rhoai-gitops** maps the `gpu.nvidia.com` DeviceClass to `nvidia.com/gpu` (`Kueue` CR `deviceClassMappings`), so `serving-lq` / `batch-lq` count claims against the same quota as before. Nothing Kueue-related changes in this repo.

## Decision

This chart **does not define GPU claim templates**: how a GPU is requested (device filters, MIG alternatives, fallbacks) is a platform decision. The chart only references one by name.

`serving.dra` in `values.yaml` (`enabled: true` by default):

- `serving.dra.claimTemplate`: name of the platform-defined `ResourceClaimTemplate` in the model namespace. Required for GPU models when DRA is on (the render fails with a clear message otherwise). The GPU count comes from the template.
- DRA on: `nvidia.com/gpu` is removed from limits/requests of the model container and replaced by `resources.claims`, plus `spec.resourceClaims` on the pod.
- DRA off (`--set serving.dra.enabled=false`): the device-plugin form, identical to before DRA support.
- CPU models (`cpu-profile`, no GPU in resources) never get a claim (`rhoai-serving.useDra` = `serving.dra.enabled` AND `hasNvidiaGpu`).
- Where the claim goes: `LLMInferenceService.spec.template.resourceClaims` and `InferenceService.spec.predictor.resourceClaims` (both CRDs accept it). The chart does not render `spec.worker` / `prefill`.

Shared sizes defined in rhoai-gitops (`templates/06-dra`), each a `firstAvailable` list so the same name lands on different hardware per cluster:

| Template | Intent | Alternatives, in order |
|----------|--------|------------------------|
| `gpu-s-x1` | small model (embeddings) | MIG `1g.12gb`, MIG `2g.24gb`, any GPU >= 16Gi |
| `gpu-m-x1` | about 24 GB, LLMs on the L4 | `NVIDIA L4`, MIG `2g.24gb`, any GPU >= 22Gi |
| `gpu-l-x1` | 1x H100 | any GPU >= 80Gi, MIG `7g.94gb` |
| `gpu-xl-x4` | 4 GPUs (tensor parallelism) | commented reference in rhoai-gitops, **not rendered yet**: infra must create it before Llama 70B is deployed |

The model files choose the size in `serving.dra.claimTemplate`: `gpu-s-x1` for the embedding models (bge-m3, nomic), `gpu-m-x1` for the 8-24B models on the L4, `gpu-l-x1` for the 1x H100 ones, `gpu-xl-x4` for Llama 70B. `gpu-s-x1` is not used for LLMs: its first alternative on a MIG cluster is a 12 GB slice, too small for the weights plus KV cache. The shared templates are created in `models-as-a-service` (`dra.namespaces` in rhoai-gitops): a model in another namespace needs it added there. A vLLM process only sees the first MIG partition of its list, so tensor parallelism needs N full GPUs (a platform concern when defining `gpu-xl-x4`).

### HardwareProfile

The `opendatahub.io/hardware-profile-*` annotation makes the RHOAI webhook apply the profile, and `HardwareProfile` identifiers have no DRA field in RHOAI 3.5.3. **Verified on the cluster** with `gpu-profile`: the webhook adds `nvidia.com/gpu: 1` to limits/requests *on top of* the claim. Kueue then counts 2 GPUs against a quota of 1 (`insufficient quota for nvidia.com/gpu ... request (2) > maximum capacity (1)`), the pod stays `SchedulingGated`, and the nodes do not advertise `nvidia.com/gpu` anyway.

Fix: **`gpu-dra-profile`** (rhoai-gitops, `templates/05-hardware-profiles`): same queue `serving-lq` and priority `model-critical`, but only CPU and memory identifiers. On DRA models whose `serving.hardwareProfile.name` is `gpu-profile` the chart writes `serving.dra.hardwareProfile` (default `gpu-dra-profile`) in the annotation, so the dashboard shows the profile instead of "Unknown". The Kueue labels keep deriving from the name in the values (`gpu-profile` and `gpu-dra-profile` both map to `serving-lq` / `model-critical`). Any other profile with DRA (for example `gpu-batch-profile`, which has no DRA variant) gets no annotation, because it would inject `nvidia.com/gpu`. `gpu-dra-profile` must exist in the cluster before the model is applied.

## Consequences

- Cluster without the NVIDIA DRA driver: set `serving.dra.enabled=false` (or the pods stay `Pending` waiting for a claim).
- Argo CD Applications that deploy GPU models on a non-DRA cluster must pass `serving.dra.enabled=false`.
- A new GPU size is a change in rhoai-gitops, not in this chart.
- `chart/README.md`: the generated values table must be regenerated with `helm-docs` (`make docs` in `chart/`).
