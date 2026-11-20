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
DeviceClass              gpu.nvidia.com / mig.nvidia.com   (created by NVIDIA, not by the chart)
   │
   ▼
ResourceClaimTemplate    <name>-gpu, in the MODEL namespace  (created by the chart)
   │  one ResourceClaim per pod
   ▼
Pod                      spec.resourceClaims[gpu] + containers[].resources.claims[gpu]
```

Kueue 1.5 evaluates the claims. **rhoai-gitops** maps the `gpu.nvidia.com` DeviceClass to `nvidia.com/gpu` (`Kueue` CR `deviceClassMappings`), so `serving-lq` / `batch-lq` count claims against the same quota as before. Nothing Kueue-related changes in this repo.

## Decision

A `serving.dra` block in `values.yaml`, **`enabled: true` by default**. The model files are untouched:

- The GPU count comes from `mainContainer.resources.limits["nvidia.com/gpu"]` (single source of truth).
- DRA on: that key is removed from limits/requests and replaced by `resources.claims`; the claim template asks for `count: N` (`exactly`, explicit `allocationMode: ExactCount` so Argo CD does not see a diff against the API-server defaults).
- DRA off (`--set serving.dra.enabled=false`): the render is byte-for-byte what it was before DRA support.
- CPU models (`cpu-profile`, no GPU in resources) never get a claim or template (`rhoai-serving.useDra` = `serving.dra.enabled` AND `hasNvidiaGpu`).
- Where the claim goes: `LLMInferenceService.spec.template.resourceClaims`, `InferenceService.spec.predictor.resourceClaims` (both CRDs accept it; DRA therefore also works for a predictive model that asks for a GPU). The chart does not render `spec.worker` / `prefill`, so nothing else needs a claim.

Device selection (all optional, CEL on the `gpu.nvidia.com` driver domain):

| Value | CEL |
|-------|-----|
| `serving.dra.productName` | `device.attributes["gpu.nvidia.com"].productName == "NVIDIA L4"` |
| `serving.dra.minMemory` | `device.capacity["gpu.nvidia.com"].memory.compareTo(quantity("40Gi")) >= 0` |
| `serving.dra.selectors[]` | free CEL expressions, all must match |

By default there is no product filter: any GPU of `gpu.nvidia.com`, so the same values run on L4 and H100.

**MIG** (`serving.dra.mig.enabled`, off by default) replaces the request with `firstAvailable`: preferred profile with its `count`, then a fallback profile with its `count`. The `profile` attribute comes from NVIDIA/Red Hat documentation and has not been verified on a MIG cluster. A vLLM process only sees the **first** MIG partition of its list, so `parallelism.tensor > 1` cannot be spread over MIG slices; the chart fails the render in that case. Tensor parallelism works with N full GPUs.

**Existing template (preferred)**: `serving.dra.claimTemplate.existing: <name>` references a `ResourceClaimTemplate` that already exists in the model namespace and the chart does not create one. The template is namespaced, so it must live in the model namespace. The platform team defines shared t-shirt sizes in rhoai-gitops (`templates/06-dra`), each one a `firstAvailable` list so the same name lands on different hardware per cluster:

| Template | Intent | Alternatives, in order |
|----------|--------|------------------------|
| `gpu-s-x1` | small model, L4 demo | MIG `1g.12gb`, MIG `2g.24gb`, any GPU >= 16Gi |
| `gpu-m-x1` | about 24 GB | `NVIDIA L4`, MIG `2g.24gb`, any GPU >= 22Gi |
| `gpu-l-x1` | 1x H100 | any GPU >= 80Gi, MIG `7g.94gb` |

The model files choose the size: `gpu-s-x1` for the small embedding models (bge-m3, nomic), `gpu-m-x1` for the 8-24B models on the L4, `gpu-l-x1` for the 1x H100 ones. `gpu-s-x1` is not used for LLMs: its first alternative on a MIG cluster is a 12 GB slice, too small for the weights plus KV cache. Multi-GPU models (Llama 70B, 4 GPUs) still use the chart-generated template until the platform defines `gpu-xl-x4` (a commented reference exists there). The shared templates are created in `models-as-a-service` (`dra.namespaces` in rhoai-gitops): a model in another namespace needs it added there. With `serving.dra.enabled=false` the setting is ignored.

### HardwareProfile

The `opendatahub.io/hardware-profile-*` annotation makes the RHOAI webhook apply the profile, and `HardwareProfile` identifiers have no DRA field in RHOAI 3.5.3. **Verified on the cluster** with `gpu-profile`: the webhook adds `nvidia.com/gpu: 1` to limits/requests *on top of* the claim. Kueue then counts 2 GPUs against a quota of 1 (`insufficient quota for nvidia.com/gpu ... request (2) > maximum capacity (1)`), the pod stays `SchedulingGated`, and the nodes do not advertise `nvidia.com/gpu` anyway.

Fix: **`gpu-dra-profile`** (rhoai-gitops, `templates/05-hardware-profiles`): same queue `serving-lq` and priority `model-critical`, but only CPU and memory identifiers. On DRA models whose `serving.hardwareProfile.name` is `gpu-profile` the chart writes `serving.dra.hardwareProfile` (default `gpu-dra-profile`) in the annotation, so model files are untouched and the dashboard shows the profile instead of "Unknown". The Kueue labels keep deriving from the name in the values (`gpu-profile` and `gpu-dra-profile` both map to `serving-lq` / `model-critical`).

For any other profile with DRA (for example `gpu-batch-profile`, which has no DRA variant) the annotation is not rendered, because that profile would inject `nvidia.com/gpu` (`serving.dra.hardwareProfileAnnotation: true` forces it). `gpu-dra-profile` must exist in the cluster before the model is applied.

## Consequences

- Cluster without the NVIDIA DRA driver: set `serving.dra.enabled=false` (or the pods stay `Pending` waiting for a claim).
- Argo CD Applications that deploy GPU models on a non-DRA cluster must pass `serving.dra.enabled=false`.
- `chart/README.md`: the generated values table must be regenerated with `helm-docs` (`make docs` in `chart/`).
