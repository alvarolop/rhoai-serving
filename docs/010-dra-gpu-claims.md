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

A `dra:` block in `values.yaml`, **`enabled: true` by default**. The model files are untouched:

- The GPU count comes from `mainContainer.resources.limits["nvidia.com/gpu"]` (single source of truth).
- DRA on: that key is removed from limits/requests and replaced by `resources.claims`; the claim template asks for `count: N` (`exactly`, explicit `allocationMode: ExactCount` so Argo CD does not see a diff against the API-server defaults).
- DRA off (`--set dra.enabled=false`): the render is byte-for-byte what it was before DRA support.
- CPU models (`cpu-profile`, no GPU in resources) never get a claim or template (`rhoai-serving.useDra` = `dra.enabled` AND `hasNvidiaGpu`).
- Where the claim goes: `LLMInferenceService.spec.template.resourceClaims`, `InferenceService.spec.predictor.resourceClaims` (both CRDs accept it; DRA therefore also works for a predictive model that asks for a GPU). The chart does not render `spec.worker` / `prefill`, so nothing else needs a claim.

Device selection (all optional, CEL on the `gpu.nvidia.com` driver domain):

| Value | CEL |
|-------|-----|
| `dra.productName` | `device.attributes["gpu.nvidia.com"].productName == "NVIDIA L4"` |
| `dra.minMemory` | `device.capacity["gpu.nvidia.com"].memory.compareTo(quantity("40Gi")) >= 0` |
| `dra.selectors[]` | free CEL expressions, all must match |

By default there is no product filter: any GPU of `gpu.nvidia.com`, so the same values run on L4 and H100.

**MIG** (`dra.mig.enabled`, off by default) replaces the request with `firstAvailable`: preferred profile with its `count`, then a fallback profile with its `count`. The `profile` attribute comes from NVIDIA/Red Hat documentation and has not been verified on a MIG cluster. A vLLM process only sees the **first** MIG partition of its list, so `parallelism.tensor > 1` cannot be spread over MIG slices; the chart fails the render in that case. Tensor parallelism works with N full GPUs.

**Existing template**: `dra.claimTemplate.existing: <name>` references a `ResourceClaimTemplate` that already exists in the model namespace and the chart does not create one. The template is namespaced, so it must live in the model namespace.

### HardwareProfile

`opendatahub.io/hardware-profile-name` makes the RHOAI webhook apply the profile; the `HardwareProfile` identifiers (`nvidia.com/gpu`) have no DRA field in RHOAI 3.5.3, so the webhook could add `nvidia.com/gpu` to the container and the pod would never schedule without a device plugin. **This has not been verified on the cluster**, so the chart avoids the risk: on DRA models the `hardware-profile-*` annotations are not rendered (`dra.hardwareProfileAnnotation: false`). The Kueue labels `queue-name` and `priority-class` keep deriving from `serving.hardwareProfile.name` (see `rhoai-serving.kueueLocalQueue` / `kueuePriorityClass`), so queueing is unchanged. The cost is that the dashboard does not show the profile on those models.

## Consequences

- Cluster without the NVIDIA DRA driver: set `dra.enabled=false` (or the pods stay `Pending` waiting for a claim).
- Argo CD Applications that deploy GPU models on a non-DRA cluster must pass `dra.enabled=false`.
- `chart/README.md`: the generated values table must be regenerated with `helm-docs` (`make docs` in `chart/`).
