# 002 — Namespace and resource identity

## Context

The chart must create predictable Kubernetes names for the dashboard, connections, RBAC, and test scripts.

## Decision

- **`name`** — Becomes **`LLMInferenceService.metadata.name`** (generative) or **`InferenceService` / `ServingRuntime` names** (predictive). Use a stable, DNS-friendly token (for example `tinyllama-1b`, `qwen3-8b`).
- **`namespace.name`** — Target namespace for all namespaced objects. The chart does not create it: the platform (rhoai-gitops) owns the namespace, its Kueue label and its LocalQueues.
- **Connection Secret** — Only created when it carries credentials: **S3** (`AWS_*` keys; **`model.s3.path`** maps to **`opendatahub.io/connection-path`**) or **OCI** with **`model.oci.dockerconfigjson`**. It is named **`{{ .Values.name }}`**, matching **`opendatahub.io/connections`** on the serving CR (written only in these cases). `hf://` and public `oci://` models need none: the URI already sits in **`spec.model.uri`** (or **`storageUri`**). The protocol is detected from the **`model.uri`** prefix (`s3://`, `oci://`, otherwise `uri`). See Red Hat *Using the connections API*.

## Consequences

- Scripts and docs refer to **`<namespace>`** and **`<LLMInferenceService name>`** as two separate arguments; they are not required to match the Helm release name.
- Reusing the same **`name`** in two namespaces is allowed; global uniqueness is only within a namespace.

## Status

Accepted; keep naming examples in `values-*.yaml` and README consistent with this layout.
