# 010 — GPUs through Dynamic Resource Allocation (DRA)

**TL;DR**

- GPU models request their GPU with a **`ResourceClaimTemplate`** (DRA) instead of `nvidia.com/gpu` limits. On by default: `serving.dra.enabled: true`.
- **This chart creates no claim templates.** Each model names a platform-defined size in `serving.dra.claimTemplate`: `gpu-s-x1`, `gpu-m-x1`, `gpu-l-x1`, `gpu-xl-x1` (rhoai-gitops, `06-dra`).
- On DRA models the hardware profile becomes **`gpu-dra-profile`** (no `nvidia.com/gpu` identifier). With `gpu-profile` the pod never schedules.
- CPU models are untouched. Cluster without the NVIDIA DRA driver: `--set serving.dra.enabled=false`.

## How it fits together

```
GPU hardware
   │  NVIDIA DRA driver
   ▼
ResourceSlice          what each node offers (model, memory, MIG profile)
   │
   ▼
DeviceClass            gpu.nvidia.com / mig.nvidia.com           created by NVIDIA
   │
   ▼
ResourceClaimTemplate  gpu-s-x1 / m-x1 / l-x1 / xl-x1   created by the platform team (rhoai-gitops)
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

Each size is a `firstAvailable` list: the same name lands on different hardware in different clusters.

| Template | For | Alternatives, in order |
|----------|-----|------------------------|
| `gpu-s-x1` | small models (embeddings) | MIG `1g.12gb`, MIG `2g.24gb`, any GPU >= 16Gi |
| `gpu-m-x1` | 8-24B LLMs on the L4 | `NVIDIA L4`, MIG `2g.24gb`, any GPU >= 22Gi |
| `gpu-l-x1` | 1x H100 | any GPU >= 80Gi, MIG `7g.94gb` |
| `gpu-xl-x1` | 1 GPU with 140 Gi or more (B200, H200) | any GPU >= 140Gi, MIG `7g.180gb`, MIG `7g.141gb` |

Models pick one in their values file (first lines of `serving:`): `gpu-s-x1` for bge-m3 and nomic, `gpu-m-x1` for the L4 LLMs, `gpu-l-x1` for Qwen3.8 and Gemma 26B, `gpu-xl-x1` for Llama 70B (FP8, 72.7 GB of weights: on an 80 GB H100 almost nothing is left for the KV cache). `gpu-s-x1` is not used for LLMs: on a MIG cluster its first option is a 12 GB slice, too small for weights plus KV cache.

## Hardware profile

The `opendatahub.io/hardware-profile-*` annotation makes the RHOAI webhook apply the profile, and `HardwareProfile` has no DRA field in RHOAI 3.5. Verified on the cluster:

```
gpu-profile      model ─webhook─▶ adds nvidia.com/gpu: 1 ─▶ Kueue counts limit + claim = 2 GPUs ─▶ SchedulingGated
gpu-dra-profile  model ─webhook─▶ CPU and memory only    ─▶ Kueue counts the claim   = 1 GPU  ─▶ Running
```

`gpu-dra-profile` (rhoai-gitops, `05-hardware-profiles`) has the same queue (`serving-lq`) and priority (`model-critical`) as `gpu-profile`. The chart swaps `gpu-profile` for `serving.dra.hardwareProfile` (default `gpu-dra-profile`) when DRA is on, so model files keep saying `gpu-profile`. Kueue labels still derive from the name in the values. Any other GPU profile (for example `gpu-batch-profile`) gets no annotation on DRA models, because it would inject `nvidia.com/gpu`.

## Operating notes

- `gpu-dra-profile` and the sizes must exist before a model is applied. The sizes are created in `models-as-a-service` (`dra.namespaces` in rhoai-gitops): a model in another namespace needs it added there.
- Llama 70B asks for `gpu-xl-x1` (one B200/H200): it does not schedule on L4 or H100 clusters. There is no multi-GPU size; add one to rhoai-gitops if tensor parallelism is needed.
- A new GPU size is a change in rhoai-gitops, not in this chart.
- The `chart/README.md` values table must be regenerated with `helm-docs` (`make docs` in `chart/`).
