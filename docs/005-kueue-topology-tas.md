# 005 — Kueue topology gates: why `SchedulingGated`, and what changed in gitops

## Context

On clusters that run the **Red Hat build of Kueue** with **distributed workloads** enabled, model serving pods (including **`LLMInferenceService`**) can be processed as **Kueue Workloads**. When **Topology Aware Scheduling (TAS)** is in play, pods may carry **scheduling gates** such as **`kueue.x-k8s.io/admission`** and **`kueue.x-k8s.io/topology`**.

A failure mode that shows up as “**stuck in Pending**” even though the **Workload** is **Admitted** and quota looks fine:

1. The pod (or workload integration) expects a **topology assignment** from Kueue TAS.
2. The **ResourceFlavor** assigned to the workload (for example **`gpu-flavor`**) had **no `spec.topologyName`** pointing at a **`Topology`** object, and therefore did not participate in TAS node scraping the way the controller expects.
3. The **topology controller** never produces a **`topologyAssignment`** the pod reconciler needs to clear **`kueue.x-k8s.io/topology`**.
4. The **default scheduler** does not run the pod while those gates remain → **Pending** with **`SchedulingGated`**.

This is not specific to one model (for example LlamaGuard); any **GPU serving** path that triggers the same TAS + flavor combination can hit it.

Upstream Kueue documents TAS as **beta** from roughly **Kueue v0.14** onward; it is **enabled by default** in many installations. The **Red Hat build of Kueue** version ships with **OpenShift** / **OpenShift AI** and moves forward on its own cadence—**there is no single chart version** that maps 1:1 to “when this exact gate sequence appears.” The practical difference between “old cluster worked” and “new cluster stuck” is usually a **combination** of:

- **Newer Kueue** with stricter or more complete TAS behavior,
- **OpenShift AI / KServe / llm-d** changes that attach **topology** expectations to serving pods,
- **Your gitops** only defining **`ResourceFlavor`** tolerations (and quotas) but **not** the **Topology + `topologyName` + `nodeLabels`** contract TAS needs.

So “it worked before” is often **older operator stacks** or **workloads that did not request topology** the same way—not that the previous configuration was strictly “correct” for TAS on every future version.

## Changes made (rhoai-gitops)

In **`rhoai-installation-chart`** (see **`templates/05-distributed-workloads/`** and **`values.yaml`**):

| Piece | Purpose |
|--------|---------|
| **`Topology`** | Cluster-scoped **`kueue.x-k8s.io/v1beta1`** `Topology` named **`rhoai-hostname`** (hardcoded) with a **single level** `kubernetes.io/hostname` so TAS has a minimal hierarchy to assign. |
| **`ResourceFlavor` `spec.topologyName`** | **`rhoai-hostname`**, matching that `Topology` (hardcoded in the flavor templates) so Kueue can **scrape** topology capacity for nodes that match the flavor. |
| **`ResourceFlavor` `spec.nodeLabels`** | **Required** with `topologyName` so Kueue knows **which nodes** belong to the flavor. **Hardcoded** in **rhoai-installation-chart** templates: GPU **`nvidia.com/gpu.deploy.device-plugin: "true"`** (NVIDIA GPU Operator), CPU **`node-role.kubernetes.io/worker: ""`**. If your cluster uses different labels, edit those templates. |
| **`distributedWorkloads.topologyAwareScheduling`** | Default **`true`**. Set **`false`** only if you must opt out (for example no `Topology` CRD on an old cluster)—understanding you may reintroduce the deadlock if the cluster still injects topology requests. The **`Topology` metadata name** and all **`spec.topologyName`** fields are the fixed string **`rhoai-hostname`** (not in values); change all three template files in lockstep if you rename it. |

Sync order: **Topology** sync-wave **9**, **ResourceFlavor** **10**, so the `Topology` exists before flavors reference it.

## Flavor assignment vs node placement (GPU vs CPU)

Kueue chooses **`cpu-flavor`** vs **`gpu-flavor`** from what the **Workload’s PodSets request** in the **`ClusterQueue`**: workloads that **do not** use accelerator quota in the CPU flavor path (no non-zero **`nvidia.com/gpu`** for that assignment) align with **`cpu-flavor`**; workloads that **request GPUs** align with **`gpu-flavor`**, which carries the **NVIDIA device-plugin** taint **toleration** and **`nvidia.com/gpu.deploy.device-plugin`** **nodeLabels**. So **GPU serving** (e.g. **`LLMInferenceService`** with GPU **resources**) is tied to **`gpu-flavor`**; **CPU-only** serving uses **`cpu-flavor`**.

**`cpu-flavor`** uses **`node-role.kubernetes.io/worker: ""`**, which matches **all** workers. **GPU nodes are usually workers too**, so that label **alone** does not exclude GPU hardware—it only bounds “worker” for Kueue’s topology / capacity accounting. In typical OpenShift + **NVIDIA GPU Operator** setups, **GPU nodes are tainted** (for example **`nvidia.com/gpu`** **NoSchedule**). Pods **without** that **toleration** (normal **CPU-only** workloads) **do not schedule** on those nodes, so they still end up on **non–GPU-tainted** workers in practice.

If your cluster **does not** taint GPU nodes, **CPU** pods could **in principle** be scheduled on GPU workers; fixing that is **cluster policy** (taints, affinity, or a **narrower** **`cpu-flavor` `nodeLabels`**), not something the hostname **`Topology`** object changes by itself.

## Consequences for rhoai-serving

- The **Helm chart** does not create Kueue **`Topology`** / **`ResourceFlavor`** objects; those stay in **gitops**. The chart still sets **`HardwareProfile`** (**`cpu-profile` / `gpu-profile`**) and queue labels consistent with **`rhoai-gitops`**.
- **Single-replica** deployments are unchanged in intent (**`replicas: 1`** by default); this issue is about **Kueue TAS**, not replica count.
- If GPU nodes **do not** show **`nvidia.com/gpu.deploy.device-plugin=true`**, edit **`resourceflavor-gpu-flavor.yaml`** to use a label your **NVIDIA GPU Operator** actually sets (see **`oc get nodes --show-labels`**, e.g. **`nvidia.com/gpu.present: "true"`**).

---

## rhoai-serving change: GPU toleration must match `gpu-flavor` (`operator: Exists`)

**Symptom:** **`Workload`** looks admitted or scheduler work runs, but the **decoder / main** pod stays **`Pending`** with **`SchedulingGated`** (`kueue.x-k8s.io/admission` + **`topology`**). **Kueue manager** logs show **`Unsuspending job`** failing with:

`Pod "…" is invalid: spec.tolerations: Forbidden: existing toleration can not be modified except its tolerationSeconds`

**Cause:** **`gpu-flavor`** in gitops declares the NVIDIA taint toleration with **`operator: Exists`**. If the **`LLMInferenceService`** pod template only had **`effect` + `key`** (implicit **`Equal`**), the live pod and Kueue’s merged toleration **differ**. On unsuspend, Kueue updates the **`Pod`**; the API server rejects that toleration change.

**Fix (chart):** **`chart/templates/llminferenceservice.yaml`** and **`chart/templates/inferenceservice.yaml`** emit the GPU toleration with **`operator: Exists`**, matching **`resourceflavor-gpu-flavor.yaml`**. Details and rationale: **[004 — GPU tolerations vs Kueue `ResourceFlavor`](004-kueue-gpu-tolerations.md)** (updated for this interaction).

**Why the llm-d router pod often looked “fine”:** The **EPP / router-scheduler** pod is **CPU-only** and usually has **no** `nvidia.com/gpu` toleration before admit. Kueue only **adds** tolerations there → no forbidden **modification**. The **main** vLLM pod carried the mismatched GPU toleration → failure.

---

## CPU-only serving (e.g. TinyLlama CPU) vs GPU (e.g. LlamaGuard): what actually differs on the cluster

These are **different Kueue paths**, not “the same topology bug twice.”

| Aspect | CPU-only path (e.g. **`values-tinyllama-1b-cpu.yaml`**) | GPU path (e.g. LlamaGuard) |
|--------|----------------------------------------|-------------------------|
| **`HardwareProfile`** | **`cpu-profile`** | **`gpu-profile`** |
| **Pod requests** | **No** non-zero **`nvidia.com/gpu`** | **`nvidia.com/gpu: "1"`** (typical) |
| **Kueue `ResourceFlavor`** | **`cpu-flavor`** (no extra tolerations in gitops) | **`gpu-flavor`** (GPU taint **`Exists`** + **`topologyName`**) |
| **Topology / gates** | TAS still applies when **`topologyAwareScheduling: true`**, but placement uses the **CPU** flavor’s node set and quotas. | TAS assigns a **hostname** slice on **GPU-labeled** nodes; gates clear only after **quota + topology** succeed **and** pod unsuspend succeeds. |

**Important — “CPU model” must not request a GPU on the live `Pod`:**  
Helm **deep-merges** `-f` values files: **`resources`** is defined per model file (base **`chart/values.yaml`** uses **`resources: {}`**). If any merged layer still leaves **`nvidia.com/gpu`** under **`resources`**, a CPU-only overlay that only sets **`cpu`** / **`memory`** does **not** remove sibling keys from another layer, so **`.Values.resources` can still contain a GPU key after merge** even when the last file never mentions GPU.

**Chart behavior:** **`rhoai-serving.hasNvidiaGpu`** (see **`chart/templates/_helpers.tpl`**) returns **`false`** when **`serving.hardwareProfile.name`** is **`cpu-profile`** (the name used in **rhoai-gitops** for CPU **`HardwareProfile`**). Then **`kserveModelResources`** **omits** **`nvidia.com/gpu`** from the rendered **`LLMInferenceService`** / **`InferenceService`** spec regardless of merged values. CPU overlays (TinyLlama CPU, etc.) should keep **`cpu-profile`** so the served pod does not compete for **`gpu-flavor`**. **Nomic** and **BGE-M3** overlays are **GPU-only** (**`gpu-profile`**).

If you use a **custom** CPU profile name, either rename it in gitops to match or duplicate the “strip GPU” behavior in your overlay (e.g. explicit **`nvidia.com/gpu: "0"`** in **`resources`** so **`hasNvidiaGpu`** stays false without relying on the **`cpu-profile`** shortcut).

**Symptom when two workloads both want 1× GPU on a small cluster:** One **`Workload`** may show **`QuotaReserved: False`** with a message like:

`topology "rhoai-hostname" doesn't allow to fit any of 1 pod(s). Total nodes: 1; excluded: resource "nvidia.com/gpu": 1`

That means: under TAS + **`gpu-flavor`** **nodeLabels**, Kueue only sees **fit** placement on nodes that match the flavor, and **no slice had a free GPU** for this pod (another pod or reservation already consumed it). The pod stays **gated** because admission/topology never completes satisfactorily for that **`Workload`**.

**Verify on the cluster:**

```bash
oc get pod -n model-tinyllama -l app.kubernetes.io/component=llminferenceservice-workload -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{.spec.containers[0].resources}{"\n---\n"}{end}'
oc get pod -n model-llamaguard   -l app.kubernetes.io/component=llminferenceservice-workload -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{.spec.containers[0].resources}{"\n---\n"}{end}'
oc get workload.kueue.x-k8s.io -n model-llamaguard -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{range .status.conditions[*]}{.type}={.status} {.message}{"\n"}{end}{"---\n"}{end}'
```

- After upgrading the chart, **`helm template`** / **`helm upgrade`** with **`-f chart/values.yaml -f …/values-tinyllama-1b-cpu.yaml`** (or equivalent **CPU** overlay): the main container **`resources`** in the **`LLMInferenceService`** YAML should **omit** **`nvidia.com/gpu`**. If an **old** pod spec still shows **`nvidia.com/gpu`**, roll the deployment or re-apply the CR so the controller reconciles from the new template.
- After gates clear, a **CPU-only vLLM image** can still **`CrashLoopBackOff`** for **application** reasons (model architecture vs vLLM version, **`trust_remote_code`**, etc.) — that is **past** Kueue; use **`oc logs`** on **`main`**.

---

## End-to-end checklist (gitops + chart)

1. **Gitops (`rhoai-installation-chart`):** **`Topology` `rhoai-hostname`** + **`ResourceFlavor`** **`topologyName: rhoai-hostname`** + **`nodeLabels`** on **CPU** and **GPU** flavors (**[changes table](#changes-made-rhoai-gitops)** above).
2. **Chart (`rhoai-serving`):** (a) GPU toleration **`operator: Exists`** when GPU is requested; (b) **`cpu-profile`** forces **`hasNvidiaGpu`** false so merged defaults do not emit GPU requests on CPU models (**CPU-only serving** subsection above).
3. **Cluster:** **`oc get nodes --show-labels`** — GPU flavor **`nodeLabels`** must match your GPU Operator.
4. **Queues:** Namespace **`kueue-managed`**, **`LocalQueue` `default`**, **`ClusterQueue`** naming matches **`values.yaml`** / **[004](004-kueue-gpu-tolerations.md)**.
5. **Debug:** **`openshift-kueue-operator`** (or install namespace) **`kueue-controller-manager`** pod with **`replica-role=leader`** logs for **`Unsuspending job`** / **`tas-topology-ungater`**; **`Workload.status.conditions`** for topology / quota messages.

## References

- Kueue: [Topology Aware Scheduling](https://kueue.sigs.k8s.io/docs/concepts/topology_aware_scheduling/)
- This repository: [README — Kueue scheduling gates](../README.md) (troubleshooting snippet)
- Related: [004 — GPU tolerations vs Kueue `ResourceFlavor`](004-kueue-gpu-tolerations.md)

## Status

Accepted; **rhoai-gitops** carries the `Topology` + flavor wiring. **rhoai-serving** documents topology symptoms, **GPU toleration / `Exists` alignment**, **CPU vs GPU Kueue paths**, and **GPU capacity / phantom GPU** checks in this file; the main README still links here for Kueue troubleshooting.
