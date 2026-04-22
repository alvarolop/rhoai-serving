# 001 — llm-d inference URL and routing

## Context

Generative models here are deployed as **`LLMInferenceService`** (KServe) with **`spec.router.gateway: {}`** for the default, non–Model-as-a-Service path (for example **`values-tinyllama-1b-cpu.yaml`**). Operators expect **llm-d** (distributed inference on the platform) to attach routing, TLS, and auth in front of the workload.

After reconciliation, users often see a URL similar to:

```text
http://inference-gateway.apps.<cluster-domain>/<segment>/<llmis-name>
```

Example:

```text
http://inference-gateway.apps.ocp.sandbox2928.opentlc.com/model-tinyllama/tinyllama-1b
```

That shape can look “non-default” if you are used to **one OpenShift Route per service** in the model namespace with a project-scoped hostname. The important point is that this URL is **not** assembled by this Helm chart.

## Decision (chart boundary)

**This chart does not define Routes, Ingresses, Gateways, or `status.url`.** It only submits the **`LLMInferenceService`** (and related Secrets, RBAC, Namespace, and so on). The **exposed URL** is owned by the **OpenShift AI / KServe / llm-d** reconciliation path and appears on the CR as **`status.url`** (consumers such as [`tests/test-generative.sh`](../tests/test-generative.sh) read that field).

We document the behavior so chart users do not try to “fix” the hostname by editing Helm values that do not exist for public URL shaping.

## How to read a typical `status.url`

Details vary by release and configuration, but a common mental model is:

1. **Host (`inference-gateway.apps…`)** — A **cluster-scoped inference entrypoint** (gateway / router layer) shared by many models, rather than a per-namespace Route hostname for each `LLMInferenceService`.
2. **Path** — Often encodes **tenant scope** (frequently aligned with the **namespace** where the CR lives, for example `model-tinyllama`) and the **resource identity** (for example `tinyllama-1b`, matching **`metadata.name`** on the `LLMInferenceService`).

So the path segments reflect **where the CR lives** and **which CR** it is, which matches the chart’s **`namespace.name`** and **`name`** values for that overlay.

## Consequences

- **Changing the public URL** (different host, path layout, or TLS) is a **platform / DSC / gateway** concern, not something you change inside **`values-tinyllama-1b-cpu.yaml`** beyond namespace and CR name (which influence the path indirectly via `status.url`).
- **Models-as-a-Service** and explicit **`router.gateway.refs`** (see **`values-tinyllama-1b-maas.yaml`**) are a **separate** routing mode; compare with your **`DataScienceCluster`** `kserve.modelsAsService` setting and product docs.
- For authoritative URL and API path rules, use **Red Hat OpenShift AI** documentation for your installed version.

## Status

Accepted for this repository as of 2026-04; revise when upgrading OpenShift AI if routing behavior changes materially.
