# 006 — Helm chart scope and ModelCar / vLLM startup logs (GPT-OSS)

## Part A — What this chart does and does not control

### What the chart deploys

The **`rhoai-serving`** Helm chart targets **OpenShift AI + KServe**. **`deploy-mode.sh`** runs **`helm template`** with **`chart/values.yaml`** plus a model-specific values file and pipes the result to **`oc apply`** (no Helm release object).

Rendered resources can include:

- **Namespace** (optional) with dashboard / optional **Kueue**-managed labels.
- **Connection Secret** (`metadata.name` == **`.Values.name`**) shaped for **uri**, **oci**, or **s3** (see **`chart/templates/secret-connection.yaml`** and **`_helpers.tpl`** **`modelConnectionProtocol`**). **S3** is never inferred from the URI alone; set **`model.connection.protocol: s3`** explicitly.
- **`hf-secret`** and **`HF_TOKEN`** on the generative worker only when **`model.uri`** starts with **`hf://`** and **`hfToken`** is non-empty.
- **Generative** (**`serving.type: generative`**): **`LLMInferenceService`** — worker **`main`**, replicas, resources, **`VLLM_ADDITIONAL_ARGS`** from **`extraArgs`**, **`extraEnv`**, optional **`mainContainer`** image/command/args, dashboard / Kueue / hardware-profile / auth annotations, optional GPU tolerations.
- **Predictive** (**`serving.type: predictive`**): **`ServingRuntime`** (OVMS-oriented container template) + **`InferenceService`** (**`RawDeployment`**).
- **`auth.enabled`**: ServiceAccount, token Secret, Role (get on that name’s **`llminferenceservices`** / **`inferenceservices`**), RoleBinding.
- **`trustyai.enabled`**: **`TrustyAIService`** + CA **`ConfigMap`** (fixed small spec).

### Preconditions (not installed by this chart)

- **OpenShift AI**, **KServe**, **Kueue** **`LocalQueue`**, **`HardwareProfile`**, Gateway / Route infrastructure, and other cluster defaults (often from **rhoai-gitops** or the product operator).
- **Generative** exposure: **`router.gateway`** is **`{}`** unless **`routerGatewayRefs`** is set; the chart does not create **`Route`** / **`Gateway`** objects.
- **Multi-node** fields on **`LLMInferenceService`** are not exposed via values (commented in template).

### Predictive path caveat

**`ServingRuntime`** lists several **`supportedModelFormats`**, but the **container image and args** are **OpenVINO Model Server**–shaped; other formats are not separately templated per runtime.

---

## Part B — GPT-OSS on OCI ModelCar: noisy vLLM logs at startup

### Reference values

**`chart/values-gpt-oss-20b.yaml`** uses an **OCI** model URI, for example:

```yaml
model:
  uri: "oci://registry.redhat.io/rhelai1/modelcar-gpt-oss-20b:1.5"
  connection:
    protocol: oci
```

Pods are **`main` + `modelcar` + `modelcar-init`**; the runtime sees the model at **`/mnt/models`**.

### Log: `Repo id must be in the form 'repo_name' or 'namespace/repo_name': '/mnt/models'`

**Hugging Face `repo_utils`** (used under vLLM / transformers) sometimes treats the model location like a **Hub repo id** first. A path **`/mnt/models`** is not valid Hub syntax, so the library logs an **ERROR**, retries, then continues with **local** resolution. This is **misleading noise**, not evidence that **`model.uri`** or the Helm chart is wrong. Successful resolution shows as architecture detection and weight load.

### Log: `Permission denied: '/mnt/models/original/config.json'`

**ModelCar** images often lay out:

- Files under **`/mnt/models`** that the **`main`** container can read for **weights** (for example **safetensors** shards).
- An **`original/`** subtree (full upstream-style tree) with **permissions or ownership** that do not match the **UID** running **vLLM** in **`main`**.

vLLM / Hugging Face code may **list or walk** the tree and hit **`original/config.json`** with **`EACCES`**, log **ERROR** (with retries) and sometimes “empty list” for that probe, while **checkpoint loading** still completes from readable paths.

**Interpretation:** not ideal log hygiene, but **common** for this stack when **`original/`** is not readable by the worker. If **`Loading safetensors checkpoint shards`** reaches **100%**, **`Starting vLLM API server`**, and **`/health`** returns **200**, serving is **healthy** despite the errors.

**Not fixable inside this Helm chart alone** — packaging (image **`chmod`** / layout) or future **vLLM / RHOAI** changes would need to skip or open that path.

### Other startup warnings (benign / informational)

Examples seen alongside the above:

- **PyTorch TF32** deprecation notice.
- **Marlin / FP4** — weight-only path when the GPU lacks native FP4 compute; possible performance tradeoff, not a deploy failure.
- **`Not enough SMs to use max_autotune_gemm`** — **torch.compile** autotune fallback on smaller GPUs.

---

## Part C — Reducing log volume (especially `/metrics` and `/health`)

Repeated lines such as **`GET /metrics HTTP/1.1` 200** come from the **uvicorn access log** on the vLLM API server. **OpenShift** (kubelet probes, **ServiceMonitor** scrapes, dashboards) hits **`/health`**, **`/metrics`**, and often **`/ping`** on a short interval. That is expected; it is not caused by the Helm chart beyond exposing the same endpoints every vLLM pod has.

### vLLM: filter access logs by path (recommended)

vLLM supports **`--disable-access-log-for-endpoints`** (comma-separated path list as the next argv token — see upstream **`vllm serve --help`** and [logging examples](https://docs.vllm.ai/en/stable/examples/others/logging_configuration/)). For **generative** models this chart joins **`extraArgs`** into **`VLLM_ADDITIONAL_ARGS`** on the **`LLMInferenceService`** **`main`** container.

**`chart/values-gpt-oss-20b.yaml`** ships with:

```yaml
extraArgs:
  - "--disable-access-log-for-endpoints"
  - "/health,/metrics,/ping"
```

That suppresses **uvicorn access** lines for those paths only; **`/v1/chat/completions`** and similar still log.

**TinyLlama CPU / MaaS** (**`quay.io/rh-aiservices-bu/vllm-cpu-openai-ubi9:0.3`**, vLLM ~**0.7**): **`api_server.py` does not define `--disable-access-log-for-endpoints`** — passing it yields **`unrecognized arguments`**. Those overlays **omit** that flag (and **`extraArgs`** for it) so the pod starts. Noisy **`/metrics`** / **`/health`** access lines are expected until a **newer** CPU vLLM image adds the flag. **`VLLM_ADDITIONAL_ARGS`** from **`extraArgs`** may be **ignored** on this entrypoint; do not rely on it for unsupported options.

### Stronger options (optional)

- **`--disable-uvicorn-access-log`** — turns off **all** uvicorn access logs (including real client traffic); use only if you accept losing request audit in pod logs.
- **`VLLM_LOGGING_LEVEL`** (**`extraEnv`**) — adjusts **vLLM application** log verbosity (for example **`WARNING`**); it does **not** remove Hugging Face **`repo_utils`** **ERROR** lines, which use separate loggers.

### Cluster-side (optional)

You can also lower **Prometheus** scrape frequency or narrow **ServiceMonitor** selectors for serving pods; that reduces scrape traffic but the **kubelet** may still probe **`/health`** unless you change the **Pod** readiness/liveness settings (usually not worth it). Prefer **vLLM**’s endpoint filter first.

---

## Part D — TinyLlama CPU (`vllm-cpu-openai-ubi9:0.3`, vLLM ~0.7): Hub id noise + logging `TypeError`

With **`--model /mnt/models`** (OCI ModelCar layout), startup may log:

1. **`HFValidationError: Repo id must be in the form ... '/mnt/models'`** from **`get_sentence_transformer_tokenizer_config`** → **`list_repo_files`** — vLLM tries a **Hub** listing using the **local** mount path, fails validation, then continues on a **local** path (same class of noise as **Part B** for **`repo_utils`**).
2. **`TypeError: not all arguments converted during string formatting`** in **`logging`** — triggered while handling (1): that vLLM build uses **`logger.error("Error getting repo files", exc)`**-style calls with a **`%`-style formatter**, which is a **logging bug in the image**, not your values.
3. **`This model supports multiple tasks ... Defaulting to 'generate'.`** — informational.

If **`Loading safetensors`**, **`Starting vLLM API server`**, and **`GET /health` 200** appear, the pod is **healthy**; treat (1)–(2) as **startup noise** unless inference fails.

---

## Status

Reference note for operators: distinguish **chart / URI correctness** from **library + ModelCar filesystem** noise at startup. Use **Part C** for access-log filtering where the **vLLM** build supports **`--disable-access-log-for-endpoints`** (not vLLM ~0.7 TinyLlama CPU). Revisit if **runtime** failures appear (tokenization, config, first inference) rather than log severity alone.
