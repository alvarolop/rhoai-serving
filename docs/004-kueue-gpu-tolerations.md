# 004 — GPU tolerations: Kueue ResourceFlavor vs chart `LLMInferenceService`

## Context

On clusters with **distributed workloads / Kueue**, GPU capacity is often modeled as a **Kueue `ResourceFlavor`** (for example **`gpu-flavor`** in **rhoai-gitops**) whose **`spec.tolerations`** include the usual NVIDIA device-plugin taint:

```yaml
tolerations:
  - effect: NoSchedule
    key: nvidia.com/gpu
    operator: Exists
```

**HardwareProfile** (for example **`gpu-profile`**) ties the dashboard and serving UX to **Kueue** (for example **`scheduling.kueue.localQueueName`**) but the **`HardwareProfile`** object itself does not have to repeat those tolerations; the description in gitops even states that taints come from the flavor.

Separately, this chart’s **`LLMInferenceService`** / **`InferenceService`** templates add that toleration under **`spec.template`** when **`rhoai-serving.hasNvidiaGpu`** is true and **`serving.gpuPodTolerations`** is true (see **`chart/templates/_helpers.tpl`**). **`hasNvidiaGpu`** is false when **`serving.hardwareProfile.name`** is **`cpu-profile`**, so CPU models do not get the GPU toleration from this chart.

## Decision

**Default: keep emitting pod-level tolerations** when **`hasNvidiaGpu`** is true (**`serving.gpuPodTolerations: true`** in **`values.yaml`**).

Reasons:

1. **Admission path** — Kueue applies **`ResourceFlavor`** tolerations when it admits work; the exact merge into **`LLMInferenceService`**-owned pods can depend on **OpenShift AI + KServe** version and code path. Explicit tolerations on the CR remain **defense in depth** so GPU pods still tolerate **`nvidia.com/gpu`** taints if a layer does not copy flavor tolerations onto the final **`Pod`** spec.
2. **Shape must match the flavor** — The chart emits **`operator: Exists`** on the GPU toleration so it matches **`gpu-flavor`** in **rhoai-gitops**. If the pod is created with a different shape (for example implicit **`Equal`** without `operator`) and Kueue then merges the flavor toleration on **unsuspend**, the apiserver can reject the Pod update with **`spec.tolerations: Forbidden: existing toleration can not be modified except its tolerationSeconds`**, leaving the pod **`SchedulingGated`** even when the **Workload** is **Admitted**. Duplicates that are **byte-for-byte identical** are fine; **conflicting shapes for the same taint are not**.
3. **Opt-out** — If you have verified on your version that **only** the flavor (or controller) supplies tolerations and you want a leaner manifest, set **`serving.gpuPodTolerations: false`** in your model values or **`--set serving.gpuPodTolerations=false`**.

## Consequences

- **Predictive** **`InferenceService`** path uses the same **`hasNvidiaGpu`** + **`gpuPodTolerations`** gate in **`inferenceservice.yaml`**; this note applies primarily to **generative** **`LLMInferenceService`**.
- After disabling **`gpuPodTolerations`**, if pods stay **`Pending`** on tainted GPU nodes, re-enable **`true`** or fix **HardwareProfile / queue / flavor** alignment.

## Status

Accepted; **`gpuPodTolerations`** added to the chart so teams can align with Kueue-only injection when they choose to.
