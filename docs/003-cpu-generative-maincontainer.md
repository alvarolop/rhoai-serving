# 003 — CPU generative `mainContainer` override

## Context

The platform default generative worker image is typically **CUDA-oriented vLLM**. For **CPU-only** TinyLlama, forcing CPU via environment alone is unreliable on some vLLM and PyTorch combinations (see upstream discussions around CPU workers and bundled PyTorch).

## Decision

For **CPU TinyLlama**, the chart exposes optional **`mainContainer.image`**, **`command`**, and **`args`** on the **`LLMInferenceService`** template so overlays can pin a **CPU vLLM image** and an explicit **OpenAI-compatible entrypoint** (same spirit as a minimal custom worker deployment, without pulling Model-as-a-Service into the default path).

When **`mainContainer.image`** is empty, the chart does **not** override the worker; the platform default applies (normal for GPU-focused overlays).

## Consequences

- **GPU resource keys** on CPU overlays are stripped in templates when **`serving.gpu`** is false so merged values files do not leave stale **`nvidia.com/gpu`** requests after Helm map merges.
- **TLS file paths** in example **`args`** assume KServe’s usual mount layout under **`/var/run/kserve/tls/`**; adjust if your platform version differs.

## Status

Accepted for CPU TinyLlama overlays; revisit when the platform ships a first-class CPU generative image that matches your cluster policy.
