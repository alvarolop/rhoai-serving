# 002 — Namespace and resource identity

## Context

The chart must create predictable Kubernetes names for the dashboard, connections, RBAC, and test scripts.

## Decision

- **`name`** — Becomes **`LLMInferenceService.metadata.name`** (generative) or **`InferenceService` / `ServingRuntime` names** (predictive). Use a stable, DNS-friendly token (for example `tinyllama-1b`, `qwen3-8b`).
- **`namespace.name`** — Target namespace for all namespaced objects. When **`namespace.create: true`**, the chart also creates that **`Namespace`** with labels such as **`kueue.openshift.io/managed`** when enabled.
- **Connection Secret** — Named **`{{ .Values.name }}`**, aligned with **`opendatahub.io/connections`** on the serving CR so the workbench can reference the same string.

## Consequences

- Scripts and docs refer to **`<namespace>`** and **`<LLMInferenceService name>`** as two separate arguments; they are not required to match the Helm release name.
- Reusing the same **`name`** in two namespaces is allowed; global uniqueness is only within a namespace.

## Status

Accepted; keep naming examples in `values-*.yaml` and README consistent with this layout.
