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
# Weights are split into ~5 GB layers (LAYER_MAX_GB) by split_layers.py, so no per-model edit is needed.
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

COPY download_model.py split_layers.py /tmp/

# Download, then group the weights into layers of about LAYER_MAX_GB (default 5) so the runtime can
# pull them in parallel. split_layers.py fails the build if the model does not fit in MAX_CHUNKS layers.
ARG LAYER_MAX_GB=5
ENV LAYER_MAX_GB=${LAYER_MAX_GB}
RUN set -ex; \
    python /tmp/download_model.py; \
    python /tmp/split_layers.py; \
    rm -f /tmp/download_model.py /tmp/split_layers.py

# Runtime image: only weights + minimal UBI micro base
FROM registry.access.redhat.com/ubi9/ubi-micro:latest

RUN mkdir -p /models

# One layer per directory built by split_layers.py (up to 10 x LAYER_MAX_GB = 50 GB by default).
# Unused chunk directories are empty: each one adds a ~1 KB layer and no weights.
# For a bigger model, raise MAX_CHUNKS in split_layers.py and add COPY lines here.
COPY --from=downloader --chown=1001:0 /models-other/ /models/
COPY --from=downloader --chown=1001:0 /models-chunk-01/ /models/
COPY --from=downloader --chown=1001:0 /models-chunk-02/ /models/
COPY --from=downloader --chown=1001:0 /models-chunk-03/ /models/
COPY --from=downloader --chown=1001:0 /models-chunk-04/ /models/
COPY --from=downloader --chown=1001:0 /models-chunk-05/ /models/
COPY --from=downloader --chown=1001:0 /models-chunk-06/ /models/
COPY --from=downloader --chown=1001:0 /models-chunk-07/ /models/
COPY --from=downloader --chown=1001:0 /models-chunk-08/ /models/
COPY --from=downloader --chown=1001:0 /models-chunk-09/ /models/
COPY --from=downloader --chown=1001:0 /models-chunk-10/ /models/

USER 1001
