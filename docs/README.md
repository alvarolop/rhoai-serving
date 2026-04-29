# Architecture notes

Short, opinionated notes for this repository’s Helm chart: what the chart **does** and **does not** control, and how that interacts with OpenShift AI, KServe, and llm-d.

| Doc | Topic |
|-----|--------|
| [001 — llm-d inference URL and routing](001-llm-d-inference-route.md) | Why `LLMInferenceService.status.url` looks like a shared `inference-gateway` host with a path prefix |
| [002 — Namespace and resource identity](002-namespace-and-resource-identity.md) | How `name`, `namespace.name`, and secrets line up |
| [003 — CPU generative `mainContainer` override](003-cpu-generative-maincontainer.md) | When and why the chart overrides the vLLM worker image |
| [004 — Kueue GPU tolerations vs chart](004-kueue-gpu-tolerations.md) | Whether to duplicate `nvidia.com/gpu` tolerations when Kueue `ResourceFlavor` already defines them |
| [005 — Kueue topology / TAS and `SchedulingGated`](005-kueue-topology-tas.md) | Why pods can stay `Pending` with topology gates, version context, and **rhoai-gitops** `Topology` + `ResourceFlavor` changes |
| [006 — Chart scope and ModelCar / vLLM startup logs](006-chart-scope-and-modelcar-startup-logs.md) | Chart scope; ModelCar / TinyLlama CPU startup noise; **Part C** access logs (vLLM version); **Part D** TinyLlama **`list_repo_files`** + logging **`TypeError`** |
| [007 — NVFP4, inference stack, GPU matrix](007-nvfp4-inference-stack-and-gpu-matrix.md) | What **NVFP4** means; **OpenShift AI / vLLM worker** vs chart scope; **NVIDIA driver / GPU Operator / GPU SKU** checks; Hopper vs Blackwell |
| [008 — Gemma 4 “A4B” naming (MoE)](008-gemma-4-a4b-moe-naming.md) | What **26B-A4B** and **`it`** denote (sparse experts, instruction-tuned)—not a date or random suffix |
| [009 — ModelCar symlinks with Hugging Face blobs](009-modelcar-symlinks-huggingface-blobs.md) | Why large models (Gemma, Llama) break in ModelCar images with symlinks; `local_dir_use_symlinks=False` fix for blob storage |

Exact hostnames and path rules can change between OpenShift AI releases; treat product docs as authoritative for your version.
