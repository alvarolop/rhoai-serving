# 005 — Appendix: Kueue topology gates (`SchedulingGated`) and flavors

> Appendix. Background for troubleshooting; you do not need it to use the chart.

**TL;DR**

- A model pod can stay `Pending` with `SchedulingGated` while its Kueue `Workload` looks fine. Kueue Topology Aware Scheduling (TAS) has not produced a topology assignment, so the gate is never cleared.
- Fix lives in **rhoai-gitops**, not here: a `Topology` (`rhoai-hostname`), plus `topologyName` and `nodeLabels` on every `ResourceFlavor`.
- The chart creates no Kueue objects and renders no tolerations: the `ResourceFlavor` owns taints, tolerations and node placement.
- CPU models must not request a GPU: `cpu-profile` makes the chart drop `nvidia.com/gpu` from the resources.

## Why a pod gets stuck

```
Workload Admitted ─▶ pod expects a topology assignment from Kueue TAS
                       └─ flavor has no topologyName / nodeLabels ─▶ no assignment ─▶ gate never clears ─▶ Pending, SchedulingGated
```

Kueue documents TAS as beta since about v0.14, enabled by default in many installs. "It worked before" usually means an older operator stack, not a correct configuration.

## What rhoai-gitops provides (`rhoai-installation-chart`, `05-distributed-workloads`)

| Piece | Purpose |
|-------|---------|
| `Topology` `rhoai-hostname` | one level, `kubernetes.io/hostname`: the minimum TAS needs |
| `ResourceFlavor.spec.topologyName` | `rhoai-hostname`, so Kueue can scrape capacity of the flavor's nodes |
| `ResourceFlavor.spec.nodeLabels` | which nodes belong to the flavor (GPU flavor: a label set by the NVIDIA GPU Operator) |
| `distributedWorkloads.topologyAwareScheduling` | default `true`; `false` only to opt out, at the risk of the same deadlock |

Sync order: `Topology` (wave 9) before `ResourceFlavor` (wave 10).

## Who owns what

| Concern | Owner |
|---------|-------|
| Taints, tolerations, node labels, quotas, topology | `ResourceFlavor` / `ClusterQueue` (rhoai-gitops) |
| Queue and priority labels on the workload | derived from the hardware profile (see [010](010-dra-gpu-claims.md)) |
| GPU request on the pod | this chart (claim with DRA, `nvidia.com/gpu` without) |

Historical symptom: `Unsuspending job` failing with `spec.tolerations: Forbidden: existing toleration can not be modified`. A toleration written by the chart with a different shape than the flavor's (`operator: Exists`) conflicted with the one Kueue merges. The chart no longer emits any, which removes the problem.

## CPU models vs GPU models

| | CPU model (`cpu-profile`) | GPU model (`gpu-profile` / `gpu-dra-profile`) |
|--|---------------------------|-----------------------------------------------|
| Pod GPU request | none | `nvidia.com/gpu` or a claim |
| Flavor | `cpu-flavor` | `gpu-flavor` |
| Topology | TAS over the CPU flavor's nodes | TAS over GPU-labelled nodes |

A CPU overlay inherits `resources` by Helm deep-merge. If a layer leaves `nvidia.com/gpu` behind, a CPU model would end up waiting for a GPU. The chart prevents it: `hasNvidiaGpu` (`_helpers.tpl`) is false for `cpu-profile`, and the GPU keys are removed. With a custom CPU profile name, set `nvidia.com/gpu: "0"` explicitly.

Two GPU workloads on a one-GPU cluster show `QuotaReserved: False` with `topology "rhoai-hostname" doesn't allow to fit any of 1 pod(s) ... excluded: resource "nvidia.com/gpu": 1`: no GPU is free, the pod waits.

## Debug

```bash
# What the container really asks for
oc get pod -n <ns> -l app.kubernetes.io/component=llminferenceservice-workload \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{.spec.containers[0].resources}{"\n---\n"}{end}'
# Why the Workload is not admitted
oc get workload.kueue.x-k8s.io -n <ns> \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{range .status.conditions[*]}{.type}={.status} {.message}{"\n"}{end}{"---\n"}{end}'
# Node labels the flavor must match
oc get nodes --show-labels
```

Kueue manager logs (`kueue-controller-manager`, leader replica) for `Unsuspending job` and `tas-topology-ungater`. After the gates clear, a pod can still crash for application reasons (architecture vs vLLM version, `trust_remote_code`): that is past Kueue, use `oc logs` on `main`.

## References

- Kueue: [Topology Aware Scheduling](https://kueue.sigs.k8s.io/docs/concepts/topology_aware_scheduling/)
