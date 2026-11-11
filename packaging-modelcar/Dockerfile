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
# Weights are split into ~5 GB layers (LAYER_MAX_GB) by split_layers.py; uncomment as many chunk COPY
# lines as the build log asks for (see packaging-modelcar/README.md).
#
# Hugging Face token (faster downloads, needed for gated models): pass it as a build secret, which is
# never stored in any layer or in the image history:
#   podman build --secret id=hf,src=.hf_token ...
# (--build-arg HF_TOKEN=... also works, but it ends up in the builder image history.)

ARG MODEL_REPO=TinyLlama/TinyLlama-1.1B-Chat-v1.0

FROM registry.access.redhat.com/ubi9/python-314:latest AS downloader
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
RUN --mount=type=secret,id=hf,required=false \
    set -ex; \
    if [ -s /run/secrets/hf ]; then export HF_TOKEN="$(cat /run/secrets/hf)"; fi; \
    python /tmp/download_model.py; \
    python /tmp/split_layers.py; \
    rm -f /tmp/download_model.py /tmp/split_layers.py

# Runtime image: only weights + minimal UBI micro base
FROM registry.access.redhat.com/ubi9/ubi-micro:latest

RUN mkdir -p /models

# One layer per directory built by split_layers.py. The build log prints how many weight layers the
# model needs: uncomment the COPY lines up to that chunk (up to 10 x LAYER_MAX_GB = 50 GB by default).
# A forgotten line makes the check below fail the build instead of producing an incomplete image.
COPY --from=downloader --chown=1001:0 /models-other/ /models/
COPY --from=downloader --chown=1001:0 /models-chunk-01/ /models/
# COPY --from=downloader --chown=1001:0 /models-chunk-02/ /models/
# COPY --from=downloader --chown=1001:0 /models-chunk-03/ /models/
# COPY --from=downloader --chown=1001:0 /models-chunk-04/ /models/
# COPY --from=downloader --chown=1001:0 /models-chunk-05/ /models/
# COPY --from=downloader --chown=1001:0 /models-chunk-06/ /models/
# COPY --from=downloader --chown=1001:0 /models-chunk-07/ /models/
# COPY --from=downloader --chown=1001:0 /models-chunk-08/ /models/
# COPY --from=downloader --chown=1001:0 /models-chunk-09/ /models/
# COPY --from=downloader --chown=1001:0 /models-chunk-10/ /models/

# Fail the build if some weights are missing, and make the model directory read-only
RUN --mount=type=bind,from=downloader,source=/meta,target=/meta \
    set -- /models/*.safetensors; \
    [ "$#" -eq "$(cat /meta/safetensors-count)" ] || { echo "ERROR: /models has $# safetensors, expected $(cat /meta/safetensors-count): uncomment more COPY lines"; exit 1; }; \
    chmod 555 /models

USER 1001
