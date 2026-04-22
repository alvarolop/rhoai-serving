# Architecture notes

Short, opinionated notes for this repository’s Helm chart: what the chart **does** and **does not** control, and how that interacts with OpenShift AI, KServe, and llm-d.

| Doc | Topic |
|-----|--------|
| [001 — llm-d inference URL and routing](001-llm-d-inference-route.md) | Why `LLMInferenceService.status.url` looks like a shared `inference-gateway` host with a path prefix |
| [002 — Namespace and resource identity](002-namespace-and-resource-identity.md) | How `name`, `namespace.name`, and secrets line up |
| [003 — CPU generative `mainContainer` override](003-cpu-generative-maincontainer.md) | When and why the chart overrides the vLLM worker image |
| [004 — Kueue GPU tolerations vs chart](004-kueue-gpu-tolerations.md) | Whether to duplicate `nvidia.com/gpu` tolerations when Kueue `ResourceFlavor` already defines them |

Exact hostnames and path rules can change between OpenShift AI releases; treat product docs as authoritative for your version.
