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

FROM registry.access.redhat.com/ubi9/python-311:latest AS downloader
ARG MODEL_REPO
ARG HF_TOKEN=""

USER root
RUN pip install --no-cache-dir "huggingface_hub>=0.24.0"

ENV MODEL_REPO=${MODEL_REPO}
ENV HF_TOKEN=${HF_TOKEN}

COPY download_model.py /tmp/download_model.py
RUN python /tmp/download_model.py && rm -f /tmp/download_model.py

# Runtime image: only weights + a minimal UBI micro base (no Python / pip in the final layer).
FROM registry.access.redhat.com/ubi9/ubi-micro:latest

COPY --from=downloader /models /models
RUN chmod -R a=rX /models

# Non-root default; OpenShift may still run as an arbitrary UID with root group — a+rX keeps reads safe.
USER 1001
