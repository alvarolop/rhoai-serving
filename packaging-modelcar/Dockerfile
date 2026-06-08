# ModelCar image for Red Hat OpenShift AI + KServe.
# Upstream expectation: model artifacts live under /models in the image; the serving stack
# mounts them at /mnt/models in the pod (see docs/006-chart-scope-and-modelcar-startup-logs.md).
#
# Reference: https://developers.redhat.com/articles/2025/01/30/build-and-deploy-modelcar-container-openshift-ai
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

# Download + split in ONE layer to avoid duplication in builder
RUN set -ex; \
    python /tmp/download_model.py && rm -f /tmp/download_model.py; \
    \
    cd /models; \
    mkdir -p /models-other; \
    \
    # Create placeholder directories for all possible shards (1-50)
    # This ensures COPY commands never fail, empty dirs add 0 bytes to final image
    for i in $(seq 1 50); do mkdir -p /models-shard-${i}; done; \
    \
    # Move actual safetensors files to numbered shard directories
    i=1; \
    for f in *.safetensors; do \
      [ -f "$f" ] || continue; \
      mv "$f" /models-shard-${i}/; \
      i=$((i + 1)); \
    done; \
    \
    find . -maxdepth 1 -type f -exec mv {} /models-other/ \; 2>/dev/null || true; \
    chmod -R a=rX /models-shard-* /models-other

# Runtime image: only weights + minimal UBI micro base
FROM registry.access.redhat.com/ubi9/ubi-micro:latest

RUN mkdir -p /models

# Copy each shard as a separate layer (one per safetensors file)
# Supporting up to 50 shards - empty dirs add no size if model has fewer
# Llama-3.1-405B has ~191 shards, but most production models have <50
COPY --from=downloader --chown=1001:0 /models-other/ /models/
COPY --from=downloader --chown=1001:0 /models-shard-1/ /models/
# COPY --from=downloader --chown=1001:0 /models-shard-2/ /models/
# COPY --from=downloader --chown=1001:0 /models-shard-3/ /models/
# COPY --from=downloader --chown=1001:0 /models-shard-4/ /models/
# COPY --from=downloader --chown=1001:0 /models-shard-5/ /models/
# COPY --from=downloader --chown=1001:0 /models-shard-6/ /models/
# COPY --from=downloader --chown=1001:0 /models-shard-7/ /models/
# COPY --from=downloader --chown=1001:0 /models-shard-8/ /models/
# COPY --from=downloader --chown=1001:0 /models-shard-9/ /models/
# COPY --from=downloader --chown=1001:0 /models-shard-10/ /models/
# COPY --from=downloader --chown=1001:0 /models-shard-7/ /models/
# COPY --from=downloader --chown=1001:0 /models-shard-8/ /models/
# COPY --from=downloader --chown=1001:0 /models-shard-9/ /models/
# COPY --from=downloader --chown=1001:0 /models-shard-10/ /models/
# COPY --from=downloader --chown=1001:0 /models-shard-11/ /models/
# COPY --from=downloader --chown=1001:0 /models-shard-12/ /models/
# COPY --from=downloader --chown=1001:0 /models-shard-13/ /models/
# COPY --from=downloader --chown=1001:0 /models-shard-14/ /models/
# COPY --from=downloader --chown=1001:0 /models-shard-15/ /models/
# COPY --from=downloader --chown=1001:0 /models-shard-16/ /models/
# COPY --from=downloader --chown=1001:0 /models-shard-17/ /models/
# COPY --from=downloader --chown=1001:0 /models-shard-18/ /models/
# COPY --from=downloader --chown=1001:0 /models-shard-19/ /models/
# COPY --from=downloader --chown=1001:0 /models-shard-20/ /models/
# COPY --from=downloader --chown=1001:0 /models-shard-21/ /models/
# COPY --from=downloader --chown=1001:0 /models-shard-22/ /models/
# COPY --from=downloader --chown=1001:0 /models-shard-23/ /models/
# COPY --from=downloader --chown=1001:0 /models-shard-24/ /models/
# COPY --from=downloader --chown=1001:0 /models-shard-25/ /models/
# COPY --from=downloader --chown=1001:0 /models-shard-26/ /models/
# COPY --from=downloader --chown=1001:0 /models-shard-27/ /models/
# COPY --from=downloader --chown=1001:0 /models-shard-28/ /models/
# COPY --from=downloader --chown=1001:0 /models-shard-29/ /models/
# COPY --from=downloader --chown=1001:0 /models-shard-30/ /models/
# COPY --from=downloader --chown=1001:0 /models-shard-31/ /models/
# COPY --from=downloader --chown=1001:0 /models-shard-32/ /models/
# COPY --from=downloader --chown=1001:0 /models-shard-33/ /models/
# COPY --from=downloader --chown=1001:0 /models-shard-34/ /models/
# COPY --from=downloader --chown=1001:0 /models-shard-35/ /models/
# COPY --from=downloader --chown=1001:0 /models-shard-36/ /models/
# COPY --from=downloader --chown=1001:0 /models-shard-37/ /models/
# COPY --from=downloader --chown=1001:0 /models-shard-38/ /models/
# COPY --from=downloader --chown=1001:0 /models-shard-39/ /models/
# COPY --from=downloader --chown=1001:0 /models-shard-40/ /models/
# COPY --from=downloader --chown=1001:0 /models-shard-41/ /models/
# COPY --from=downloader --chown=1001:0 /models-shard-42/ /models/
# COPY --from=downloader --chown=1001:0 /models-shard-43/ /models/
# COPY --from=downloader --chown=1001:0 /models-shard-44/ /models/
# COPY --from=downloader --chown=1001:0 /models-shard-45/ /models/
# COPY --from=downloader --chown=1001:0 /models-shard-46/ /models/
# COPY --from=downloader --chown=1001:0 /models-shard-47/ /models/
# COPY --from=downloader --chown=1001:0 /models-shard-48/ /models/
# COPY --from=downloader --chown=1001:0 /models-shard-49/ /models/
# COPY --from=downloader --chown=1001:0 /models-shard-50/ /models/

USER 1001
