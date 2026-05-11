# ModelCar image for Red Hat OpenShift AI + KServe.
# Upstream expectation: model artifacts live under /models in the image; the serving stack
# mounts them at /mnt/models in the pod (see docs/006-chart-scope-and-modelcar-startup-logs.md).
#
# Reference: https://developers.redhat.com/articles/2025/01/30/build-and-deploy-modelcar-container-openshift-ai
#
# Layer splitting: Multiple COPY commands create smaller layers to avoid Quay's 20GB limit.
# See: https://access.redhat.com/solutions/7088073
#
# Default weights: TinyLlama-1.1B-Chat (small, public) — override at build time:
#   podman build --platform linux/amd64 -f packaging-modelcar/Dockerfile packaging-modelcar \
#     --build-arg MODEL_REPO=ibm-granite/granite-3.1-2b-instruct \
#     -t quay.io/<org>/modelcar-tinyllama:demo
#
# Gated models: pass secret build-arg (not persisted in layers if you use --secret):
#   podman build --secret id=hf,src=$HOME/.cache/huggingface/token ...
# and teach download_model.py to read that file if you extend it; or use:
#   --build-arg HF_TOKEN=...  (less ideal: ends up in image history unless BuildKit secrets).

ARG MODEL_REPO=TinyLlama/TinyLlama-1.1B-Chat-v1.0

FROM registry.access.redhat.com/ubi9/python-312:latest AS downloader
ARG MODEL_REPO
ARG HF_TOKEN=""

USER root
RUN pip install --no-cache-dir "huggingface_hub>=0.24.0"

ENV MODEL_REPO=${MODEL_REPO}
ENV HF_TOKEN=${HF_TOKEN}

COPY download_model.py /tmp/download_model.py
RUN python /tmp/download_model.py && rm -f /tmp/download_model.py

# Split large models into chunks to create smaller layers (avoid Quay 20GB limit)
# For models like Llama-70B with 15x 4GB shards = 60GB total
# Split into: configs (<1MB) + 4 chunks of ~15GB each
RUN set -ex; \
    cd /models; \
    mkdir -p /models-config /models-chunk1 /models-chunk2 /models-chunk3 /models-chunk4; \
    \
    # Move config files
    for ext in json txt model; do \
      find . -maxdepth 1 -type f -name "*.$ext" -exec mv {} /models-config/ \; 2>/dev/null || true; \
    done; \
    \
    # Split safetensors shards: 4 files per chunk (~16GB each for typical 4GB shards)
    i=0; \
    for f in *-of-*.safetensors; do \
      [ -f "$f" ] || continue; \
      chunk=$((i / 4 + 1)); \
      mv "$f" /models-chunk${chunk}/ 2>/dev/null || true; \
      i=$((i + 1)); \
    done; \
    \
    # Everything else (single-file models, etc.) stays in /models
    :

# Runtime image: only weights + minimal UBI micro base
FROM registry.access.redhat.com/ubi9/ubi-micro:latest

RUN mkdir -p /models

# Each COPY creates one layer - split to stay under 20GB per layer
COPY --from=downloader /models-config/ /models/
COPY --from=downloader /models-chunk1/ /models/
COPY --from=downloader /models-chunk2/ /models/
COPY --from=downloader /models-chunk3/ /models/
COPY --from=downloader /models-chunk4/ /models/
COPY --from=downloader /models/ /models/

RUN chmod -R a=rX /models

# Non-root default; OpenShift may still run as an arbitrary UID with root group — a+rX keeps reads safe.
USER 1001
