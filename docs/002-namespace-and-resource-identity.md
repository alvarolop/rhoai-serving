# 002 — Namespace and resource identity

## Context

The chart must create predictable Kubernetes names for the dashboard, connections, RBAC, and test scripts.

## Decision

- **`name`** — Becomes **`LLMInferenceService.metadata.name`** (generative) or **`InferenceService` / `ServingRuntime` names** (predictive). Use a stable, DNS-friendly token (for example `tinyllama-1b`, `qwen3-8b`).
- **`namespace.name`** — Target namespace for all namespaced objects. When **`namespace.create: true`**, the chart also creates that **`Namespace`** with labels such as **`kueue.openshift.io/managed`** when enabled.
- **Connection Secret** — Named **`{{ .Values.name }}`**, aligned with **`opendatahub.io/connections`** on the serving CR. **`model.connection.protocol`** selects **`uri`** (**`data.URI`**, **`connection-type-ref: uri-v1`**), **`oci`** (**`data.OCI_HOST`**, **`oci-v1`**, optional **`data[".dockerconfigjson"]`**), or **`s3`** (**`data`** AWS keys, **`opendatahub.io/managed`**, **`connection-type`** + **`connection-type-ref: s3`**). For **`s3`**, **`model.connection.s3.path`** maps to **`opendatahub.io/connection-path`** when set. See **`model.connection`** in `chart/values.yaml` and Red Hat *Using the connections API* (Working on data science projects).

## Consequences

- Scripts and docs refer to **`<namespace>`** and **`<LLMInferenceService name>`** as two separate arguments; they are not required to match the Helm release name.
- Reusing the same **`name`** in two namespaces is allowed; global uniqueness is only within a namespace.

## Status

Accepted; keep naming examples in `values-*.yaml` and README consistent with this layout.
