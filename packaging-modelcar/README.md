# ModelCar Builder

Build OCI container images with HuggingFace model weights for Red Hat OpenShift AI.

## Prerequisites

**HuggingFace Token:** Create `.hf_token` in repo root (see `.hf_token.example`). It is passed to the build as a secret (`--secret id=hf,src=.hf_token`), so it is never stored in the image or its history. Not required for public models, but downloads are faster and gated models need it.
```bash
echo "hf_yourTokenHere" > .hf_token
```

## Quick Start

### Build and Push

```bash
# Build ModelCar image
podman build --platform linux/amd64 \
  -f packaging-modelcar/Dockerfile packaging-modelcar \
  --build-arg MODEL_REPO=RedHatAI/gemma-4-26B-A4B-it-FP8-Dynamic \
  --secret id=hf,src=.hf_token \
  -t quay.io/alopezme/modelcar-gemma-4-26b-a4b-fp8:latest

# Push to registry
podman push quay.io/alopezme/modelcar-gemma-4-26b-a4b-fp8:latest
```

### Common Examples

**Granite 4.1 8B FP8 (L4):**
```bash
podman build --platform linux/amd64 \
  -f packaging-modelcar/Dockerfile packaging-modelcar \
  --build-arg MODEL_REPO=RedHatAI/granite-4.1-8b-fp8 \
  --secret id=hf,src=.hf_token \
  -t quay.io/alopezme/modelcar-granite-4.1-8b-fp8:latest
podman push quay.io/alopezme/modelcar-granite-4.1-8b-fp8:latest
```

**Gemma 4 12B FP8-Dynamic (L4):**
```bash
podman build --platform linux/amd64 \
  -f packaging-modelcar/Dockerfile packaging-modelcar \
  --build-arg MODEL_REPO=RedHatAI/gemma-4-12B-it-FP8-Dynamic \
  --secret id=hf,src=.hf_token \
  -t quay.io/alopezme/modelcar-gemma-4-12b-it-fp8-dynamic:latest
podman push quay.io/alopezme/modelcar-gemma-4-12b-it-fp8-dynamic:latest
```

**Gemma 4 31B FP8-Dynamic (recommended for H100):**
```bash
podman build --platform linux/amd64 \
  -f packaging-modelcar/Dockerfile packaging-modelcar \
  --build-arg MODEL_REPO=RedHatAI/gemma-4-31B-it-FP8-Dynamic \
  --secret id=hf,src=.hf_token \
  -t quay.io/alopezme/modelcar-gemma-4-31b-fp8:latest
```

**TinyLlama (default, for testing):**
```bash
podman build --platform linux/amd64 \
  -f packaging-modelcar/Dockerfile packaging-modelcar \
  --secret id=hf,src=.hf_token \
  -t quay.io/alopezme/modelcar-tinyllama:demo
```

**Meta Llama models:**
```bash
podman build --platform linux/amd64 \
  -f packaging-modelcar/Dockerfile packaging-modelcar \
  --build-arg MODEL_REPO=meta-llama/Llama-3.1-8B-Instruct \
  --secret id=hf,src=.hf_token \
  -t quay.io/alopezme/modelcar-llama-3.1-8b:latest
```

**Granite Guardian 4.1 8B (guardrails/moderation):**
```bash
podman build --platform linux/amd64 \
  -f packaging-modelcar/Dockerfile packaging-modelcar \
  --build-arg MODEL_REPO=ibm-granite/granite-guardian-4.1-8b \
  --secret id=hf,src=.hf_token \
  -t quay.io/alopezme/modelcar-granite-guardian-4.1-8b:latest
```

**Devstral Small 2 24B Instruct (agentic coding, 256k context):**
```bash
podman build --platform linux/amd64 \
  -f packaging-modelcar/Dockerfile packaging-modelcar \
  --build-arg MODEL_REPO=mistralai/Devstral-Small-2-24B-Instruct-2512 \
  --secret id=hf,src=.hf_token \
  -t quay.io/alopezme/modelcar-devstral-small-2-24b:latest
```

## Image Structure

- **Layers:** `split_layers.py` groups the weights into layers of about 5 GB (`--build-arg LAYER_MAX_GB=5`), so the runtime pulls them in parallel and no layer exceeds the Quay limit (20 GB). No per-model edit of the Dockerfile is needed. Up to 10 layers (50 GB); a bigger model makes the build fail with an explicit error (raise `MAX_CHUNKS` in `split_layers.py` and add `COPY` lines). A single file larger than 5 GB gets a layer of its own. Unused layers are empty (~1 KB).
- **Base:** UBI 9 Python 3.12 (builder) → UBI Micro (runtime)
- **Model location:** `/models` in the image
- **Runtime mount:** KServe mounts at `/mnt/models` in the pod
- **Permissions:** World-readable (`a=rX`), runs as UID 1001

## Notes

- 📦 **Image size:** Matches model size (~5-60GB depending on model)
- ⏱️ **Build time:** Depends on download speed (HuggingFace → ~10-30min for large models)
- 🔐 **Private registry:** Add `.dockerconfigjson` to `model.oci.dockerconfigjson` in values file
- ⚡ **Mistral models:** Automatically excludes `consolidated*.safetensors` (Mistral's native format) and downloads only `model-*.safetensors` (standard HuggingFace format) since vLLM uses the HF format by default. This **cuts image size in half** (~48GB → ~24GB for Devstral).

## Safetensors Format (Mistral Models)

Mistral models on HuggingFace include **two copies** of weights:
- `consolidated-*.safetensors` - Mistral's native format (requires `--load-format mistral` in vLLM)
- `model-*.safetensors` - Standard HuggingFace format (vLLM default)

**Our download script excludes consolidated format** to avoid duplicate weights. If you need the Mistral format, override:
```bash
podman build \
  --build-arg HF_IGNORE_PATTERNS="" \
  ...
```

## Reference

- [Red Hat Developer: ModelCar Guide](https://developers.redhat.com/articles/2025/01/30/build-and-deploy-modelcar-container-openshift-ai)
- Chart docs: `docs/006-chart-scope-and-modelcar-startup-logs.md`
