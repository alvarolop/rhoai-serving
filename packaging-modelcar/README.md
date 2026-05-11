# ModelCar Builder

Build OCI container images with HuggingFace model weights for Red Hat OpenShift AI.

## Prerequisites

**HuggingFace Token:** Create `.hf_token` in repo root (see `.hf_token.example`)
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
  --build-arg HF_TOKEN=$(cat .hf_token) \
  -t quay.io/alopezme/modelcar-gemma-4-26b-a4b-fp8:latest

# Push to registry
podman push quay.io/alopezme/modelcar-gemma-4-26b-a4b-fp8:latest
```

### Common Examples

**Gemma 4 31B FP8-Dynamic (recommended for H100):**
```bash
podman build --platform linux/amd64 \
  -f packaging-modelcar/Dockerfile packaging-modelcar \
  --build-arg MODEL_REPO=RedHatAI/gemma-4-31B-it-FP8-Dynamic \
  --build-arg HF_TOKEN=$(cat .hf_token) \
  -t quay.io/alopezme/modelcar-gemma-4-31b-fp8:latest
```

**Gemma 4 26B NVFP4 (tested on L4):**
```bash
podman build --platform linux/amd64 \
  -f packaging-modelcar/Dockerfile packaging-modelcar \
  --build-arg MODEL_REPO=RedHatAI/gemma-4-26B-A4B-it-NVFP4 \
  --build-arg HF_TOKEN=$(cat .hf_token) \
  -t quay.io/alopezme/modelcar-gemma-4-26b-nvfp4:latest
```

**TinyLlama (default, for testing):**
```bash
podman build --platform linux/amd64 \
  -f packaging-modelcar/Dockerfile packaging-modelcar \
  --build-arg HF_TOKEN=$(cat .hf_token) \
  -t quay.io/alopezme/modelcar-tinyllama:demo
```

**Meta Llama models:**
```bash
podman build --platform linux/amd64 \
  -f packaging-modelcar/Dockerfile packaging-modelcar \
  --build-arg MODEL_REPO=meta-llama/Llama-3.1-8B-Instruct \
  --build-arg HF_TOKEN=$(cat .hf_token) \
  -t quay.io/alopezme/modelcar-llama-3.1-8b:latest
```

**Granite Guardian 4.1 8B (guardrails/moderation):**
```bash
podman build --platform linux/amd64 \
  -f packaging-modelcar/Dockerfile packaging-modelcar \
  --build-arg MODEL_REPO=ibm-granite/granite-guardian-4.1-8b \
  --build-arg HF_TOKEN=$(cat .hf_token) \
  -t quay.io/alopezme/modelcar-granite-guardian-4.1-8b:latest
```

## Image Structure

- **Base:** UBI 9 Python 3.12 (builder) → UBI Micro (runtime)
- **Model location:** `/models` in the image
- **Runtime mount:** KServe mounts at `/mnt/models` in the pod
- **Permissions:** World-readable (`a=rX`), runs as UID 1001
- **Layer splitting:** Model files are copied in multiple layers (configs + 4 chunks of safetensors) to stay under Quay's 20GB per-layer limit. Small models use fewer layers automatically.

## Notes

- 📦 **Image size:** Matches model size (~5-60GB depending on model)
- ⏱️ **Build time:** Depends on download speed (HuggingFace → ~10-30min for large models)
- 🔐 **Private registry:** Add `.dockerconfigjson` to `model.connection.oci` in values file
- 🐛 **Symlink fix:** `download_model.py` uses `local_dir_use_symlinks=False` (see docs/009-modelcar-symlinks-huggingface-blobs.md)
- 📦 **Layer splitting:** Dockerfile splits large models into multiple layers (~4 files per chunk) to avoid Quay's 20GB layer limit. If you still hit limits, increase `MAXIMUM_LAYER_SIZE` in Quay config.yaml ([KCS #7088073](https://access.redhat.com/solutions/7088073))

## Reference

- [Red Hat Developer: ModelCar Guide](https://developers.redhat.com/articles/2025/01/30/build-and-deploy-modelcar-container-openshift-ai)
- Chart docs: `docs/006-chart-scope-and-modelcar-startup-logs.md`
