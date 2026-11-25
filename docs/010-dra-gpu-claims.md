# 010 — GPUs through Dynamic Resource Allocation (DRA)

**TL;DR**

- GPU models request their GPU with a **`ResourceClaimTemplate`** (DRA) instead of `nvidia.com/gpu` limits. On by default: `serving.dra.enabled: true`.
- **This chart creates no claim templates.** Each model names a platform-defined size in `serving.dra.claimTemplate`: `gpu-s-x1`, `gpu-m-x1`, `gpu-l-x1`, `gpu-xl-x1`, `gpu-xl-x2` (rhoai-gitops, `06-dra`).
- On DRA models the hardware profile becomes **`gpu-dra-profile`** (no `nvidia.com/gpu` identifier). With `gpu-profile` the pod never schedules.
- CPU models are untouched. Cluster without the NVIDIA DRA driver: `--set serving.dra.enabled=false`.

## How it fits together

```
GPU hardware
   │  NVIDIA DRA driver
   ▼
ResourceSlice          what each node offers (model, memory)
   │
   ▼
DeviceClass            gpu.nvidia.com (and mig.nvidia.com)       created by NVIDIA
   │
   ▼
ResourceClaimTemplate  gpu-s-x1 / m-x1 / l-x1 / xl-x1 / xl-x2   created by the platform team (rhoai-gitops)
   │  one ResourceClaim per pod
   ▼
Pod                    resourceClaims + resources.claims          written by THIS chart
```

Kueue counts the claim against the same quota as before, because rhoai-gitops maps the `gpu.nvidia.com` DeviceClass to `nvidia.com/gpu` (`deviceClassMappings`). Nothing Kueue-related changes here.

## What the chart does

| | `serving.dra.enabled: true` (default) | `false` (device plugin) |
|---|---|---|
| Container resources | `claims: [{name: gpu}]`, no `nvidia.com/gpu` | `nvidia.com/gpu` in limits/requests |
| Pod | `resourceClaims: [{name: gpu, resourceClaimTemplateName: <size>}]` | nothing |
| GPU count | from the template | from `nvidia.com/gpu` in the values |
| Hardware profile annotation | `gpu-dra-profile` | as in the values |

- Applies to `LLMInferenceService` (`spec.template`) and to a predictive `InferenceService` that asks for a GPU (`spec.predictor`).
- A model with a GPU and no `serving.dra.claimTemplate` fails the render with a clear message.
- CPU models (`cpu-profile` or no GPU in the resources) never get a claim.

## Sizes (platform-defined)

Each size is **one `exactly` request with a CEL selector on the memory** of a full GPU, so the same name fits different clusters by memory, not by device type.

| Template | For | Request |
|----------|-----|---------|
| `gpu-s-x1` | small models (embeddings) | 1 GPU with 16 Gi or more |
| `gpu-m-x1` | 8-12B LLMs on the L4 | 1 GPU with 22 Gi or more (the L4 reports 23034 Mi) |
| `gpu-l-x1` | 1x H100 | 1 GPU with 78 Gi or more (H100 80GB reports 79.6 Gi) |
| `gpu-xl-x1` | 1 GPU with 140 Gi or more (B200, H200) | 1 GPU with 140 Gi or more |
| `gpu-xl-x2` | 2 GPUs, tensor parallelism (needs `parallelism.tensor: 2`) | 2 GPUs with 78 Gi or more each |

Where each size lands:

| Cluster | `gpu-s-x1` | `gpu-m-x1` | `gpu-l-x1` | `gpu-xl-x1` | `gpu-xl-x2` |
|---|---|---|---|---|---|
| L4 only | the L4 | the L4 | does not schedule | does not schedule | does not schedule |
| H100 | whole H100 | whole H100 | whole H100 | does not schedule | 2 whole H100 (needs 2 on the node) |
| B200 / H200 | whole GPU | whole GPU | whole GPU | whole GPU | 2 whole GPUs |

A small model on a big card takes the whole card.

### Why not `firstAvailable` (MIG first, then a full GPU)

DRA lets a claim list alternatives (`firstAvailable`), for example a MIG slice first and a full GPU by memory second. **Kueue does not admit such a workload**: the pod stays `SchedulingGated` and the Workload `Inadmissible` with `FirstAvailable device selection is not supported`. It is behind an alpha gate (`KueueDRAIntegrationPrioritizedList`, off by default, not for production). The support is expected with Kueue 1.6, which is not available yet, so the sizes stay as single exact requests. The `firstAvailable` version with the MIG alternatives (`1g.12gb`, `2g.24gb`, `7g.94gb`, ...) is kept commented at the end of each `x1` template in rhoai-gitops `06-dra`, for when Kueue supports it. Those alternatives also need MIG devices (the `DynamicMIG` gate in the `GPUCluster`, alpha, or partitions already created) and are untested.

Models pick one in their values file (first lines of `serving:`): `gpu-s-x1` for bge-m3 and nomic, `gpu-m-x1` for the L4 LLMs, `gpu-l-x1` for Qwen3.8, Gemma 26B, Devstral and Nemotron Lightning 30B, `gpu-xl-x2` for Llama 70B (2 GPUs, `parallelism.tensor: 2`: the parallelism showcase). `gpu-xl-x1` (one B200/H200) is not used by any model yet. `gpu-s-x1` is not used for LLMs: a 16 Gi minimum is too small for the weights plus the KV cache of an 8B model.

## Hardware profile

The `opendatahub.io/hardware-profile-*` annotation makes the RHOAI webhook apply the profile, and `HardwareProfile` has no DRA field in RHOAI 3.5. Verified on the cluster:

```
gpu-profile      model ─webhook─▶ adds nvidia.com/gpu: 1 ─▶ Kueue counts limit + claim = 2 GPUs ─▶ SchedulingGated
gpu-dra-profile  model ─webhook─▶ CPU and memory only    ─▶ Kueue counts the claim   = 1 GPU  ─▶ Running
```

`gpu-dra-profile` (rhoai-gitops, `05-hardware-profiles`) has the same queue (`serving-lq`) and priority (`model-critical`) as `gpu-profile`. The chart swaps `gpu-profile` for `serving.dra.hardwareProfile` (default `gpu-dra-profile`) when DRA is on, so model files keep saying `gpu-profile`. Kueue labels still derive from the name in the values. Any other GPU profile (for example `gpu-batch-profile`) gets no annotation on DRA models, because it would inject `nvidia.com/gpu`.

## Operating notes

- `gpu-dra-profile` and the sizes must exist before a model is applied. The sizes are created in `models-as-a-service` (`dra.namespaces` in rhoai-gitops): a model in another namespace needs it added there.
- With a multi-GPU size the model must set `parallelism.tensor` to the same number of GPUs (Llama 70B: `gpu-xl-x2`, `tensor: 2`); the count lives in the platform template, so the two have to be kept in step.
- Llama 70B does not schedule on L4-only or single-GPU clusters.
- A new GPU size is a change in rhoai-gitops, not in this chart.
- The `chart/README.md` values table must be regenerated with `helm-docs` (`make docs` in `chart/`).
