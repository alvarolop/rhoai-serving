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
# Weight layers: 1 -> the Dockerfile works as is (chunk-01 only). It is a single 28.6 GB file: check that your registry accepts layers that big (Quay: 20 GB)
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
# Weight layers: 2 -> uncomment COPY /models-chunk-02 in the Dockerfile
podman build --platform linux/amd64 \
  -f packaging-modelcar/Dockerfile packaging-modelcar \
  --build-arg MODEL_REPO=RedHatAI/granite-4.1-8b-fp8 \
  --secret id=hf,src=.hf_token \
  -t quay.io/alopezme/modelcar-granite-4.1-8b-fp8:latest
podman push quay.io/alopezme/modelcar-granite-4.1-8b-fp8:latest
```

**Gemma 4 12B FP8-Dynamic (L4):**
```bash
# Weight layers: 1 -> the Dockerfile works as is (chunk-01 only)
podman build --platform linux/amd64 \
  -f packaging-modelcar/Dockerfile packaging-modelcar \
  --build-arg MODEL_REPO=RedHatAI/gemma-4-12B-it-FP8-Dynamic \
  --secret id=hf,src=.hf_token \
  -t quay.io/alopezme/modelcar-gemma-4-12b-it-fp8-dynamic:latest
podman push quay.io/alopezme/modelcar-gemma-4-12b-it-fp8-dynamic:latest
```

**Gemma 4 31B FP8-Dynamic (recommended for H100):**
```bash
# Weight layers: 2 -> uncomment COPY /models-chunk-02 in the Dockerfile
podman build --platform linux/amd64 \
  -f packaging-modelcar/Dockerfile packaging-modelcar \
  --build-arg MODEL_REPO=RedHatAI/gemma-4-31B-it-FP8-Dynamic \
  --secret id=hf,src=.hf_token \
  -t quay.io/alopezme/modelcar-gemma-4-31b-fp8:latest
```

**TinyLlama (default, for testing):**
```bash
# Weight layers: 1 -> the Dockerfile works as is (chunk-01 only)
podman build --platform linux/amd64 \
  -f packaging-modelcar/Dockerfile packaging-modelcar \
  --secret id=hf,src=.hf_token \
  -t quay.io/alopezme/modelcar-tinyllama:demo
```

**Meta Llama models:**
```bash
# Weight layers: 4 -> uncomment COPY /models-chunk-02..04 in the Dockerfile
podman build --platform linux/amd64 \
  -f packaging-modelcar/Dockerfile packaging-modelcar \
  --build-arg MODEL_REPO=meta-llama/Llama-3.1-8B-Instruct \
  --secret id=hf,src=.hf_token \
  -t quay.io/alopezme/modelcar-llama-3.1-8b:latest
```

**Granite Guardian 4.1 8B (guardrails/moderation):**
```bash
# Weight layers: 4 -> uncomment COPY /models-chunk-02..04 in the Dockerfile
podman build --platform linux/amd64 \
  -f packaging-modelcar/Dockerfile packaging-modelcar \
  --build-arg MODEL_REPO=ibm-granite/granite-guardian-4.1-8b \
  --secret id=hf,src=.hf_token \
  -t quay.io/alopezme/modelcar-granite-guardian-4.1-8b:latest
```

**Devstral Small 2 24B Instruct (agentic coding, 256k context):**
```bash
# Weight layers: 6 -> uncomment COPY /models-chunk-02..06 in the Dockerfile
podman build --platform linux/amd64 \
  -f packaging-modelcar/Dockerfile packaging-modelcar \
  --build-arg MODEL_REPO=mistralai/Devstral-Small-2-24B-Instruct-2512 \
  --secret id=hf,src=.hf_token \
  -t quay.io/alopezme/modelcar-devstral-small-2-24b:latest
```

## Image Structure

- **Layers:** `split_layers.py` groups the weights into layers of about 5 GB (`--build-arg LAYER_MAX_GB=5`), so the runtime pulls them in parallel. The Dockerfile has `COPY` lines for `/models-chunk-01` to `/models-chunk-10`, with only the first one active: uncomment up to the chunk count that the build log prints (`Split /models: ... uncomment COPY lines up to /models-chunk-NN`), or see the `# Weight layers` comment next to each command below. If you forget one, the build fails (`/models has X safetensors, expected Y`) instead of producing an incomplete image. A single file bigger than 5 GB gets a layer of its own, and Quay rejects layers over 20 GB.
- **Read-only:** files are `r--r--r--` and `/models` is `r-xr-xr-x`, since vLLM only reads the model.
- **Base:** UBI 9 Python 3.14 (builder) → UBI Micro (runtime)
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
# Weight layers: 1 -> the Dockerfile works as is (chunk-01 only)
podman build \
  --build-arg HF_IGNORE_PATTERNS="" \
  ...
```

## Reference

- [Red Hat Developer: ModelCar Guide](https://developers.redhat.com/articles/2025/01/30/build-and-deploy-modelcar-container-openshift-ai)
- Chart docs: `docs/006-chart-scope-and-modelcar-startup-logs.md`
