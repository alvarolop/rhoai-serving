# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Purpose

This repository provides **production-ready Helm charts** and **GitOps ArgoCD Applications** for deploying Predictive and Generative AI models on OpenShift using Red Hat OpenShift AI (RHOAI). The goal is to create clear, concise, and maintainable Helm charts that simplify the deployment and ongoing maintenance of model serving workloads.

The Helm charts use KServe in **Raw deployment** mode for maximum flexibility and will be continuously updated as new KServe features become available (e.g., llm-d integration, new router features, vLLM omni mode).

ArgoCD Applications are provided for each serving scenario, integrating the base Helm charts to enable **one-click model deployment** via GitOps workflows.

## Design Philosophy

- **Clarity over complexity** - Helm charts should be easy to understand and modify
- **Maintainability first** - Structured to simplify future updates and feature additions
- **Production-ready** - Charts are designed for real-world deployment scenarios
- **Future-proof** - Regular updates to incorporate latest KServe and runtime features

## Serving Scenarios

The Helm charts cover five distinct model serving scenarios:

1. **Predictive model serving** - Using OpenVINO runtime
2. **Generative model serving** - Using vLLM runtime (single GPU)
3. **Distributed generative model serving** - Using vLLM across multiple GPUs
4. **Accelerated generative model serving** - Using vLLM with llm-d for inference acceleration
5. **Embeddings model serving** - Using OpenVINO runtime

## Key Technologies

- **OpenShift Container Platform 4.20+** - Base platform
- **OpenShift AI (RHOAI)** - AI/ML platform layer
- **KServe** - Model serving orchestration (Raw deployment mode)
- **OpenVINO** - Intel's inference runtime for predictive models and embeddings
- **vLLM** - High-throughput LLM serving runtime
- **llm-d** - Inference acceleration framework

## Prerequisites

Required cluster components (can be installed via referenced GitOps repositories):
- OpenShift GitOps
- OpenShift AI with dependencies:
  - OpenShift Pipelines
  - Kueue
  - Node Feature Discovery
  - Nvidia GPU Operator
  - Authorino

## Evolution and Updates

This repository is a living codebase that tracks the evolution of KServe and model serving capabilities. As new features are released, the Helm charts will be updated to incorporate:

- **llm-d** - Inference acceleration integration
- **New router features** - Advanced routing and load balancing capabilities
- **vLLM omni mode** - Multi-modal model serving
- **Other KServe enhancements** - As they become available in RHOAI

The Helm chart structure is designed to make these future additions straightforward and maintainable.

## Helm Chart: rhoai-serving

The core of this repository is the **rhoai-serving** Helm chart, designed with a clean and intuitive structure to support multiple model serving scenarios through configurable values.

### Two-Layer Values Architecture

1. **`chart/values.yaml`** - Defaults for **generative** (vLLM) single-GPU serving and full schema reference (all keys documented)
2. **`chart/values-<model>.yaml`** - Model identity (`name`, `namespace.name`, model URI) and overrides (resources, `extraArgs`, TrustyAI, etc.). The base `values.yaml` documents `namespace.create`, `namespace.displayName`, `namespace.description`, and `namespace.kueueManaged` (default `true`: sets `kueue.openshift.io/managed=true` on created namespaces for Red Hat Kueue).

Predictive examples (OpenVINO) include `serving.type: predictive`, CPU resources, and `runtime` in the same model file (see `values-distilbert.yaml`).

Usage:

```
helm template <release> chart/ \
  -f chart/values.yaml \
  -f chart/values-<model>.yaml
```

### Extra Arguments and Environment Variables

The chart supports `extraArgs` and `extraEnv` for runtime customization:

- **Generative models**: `extraArgs` items are joined into the `VLLM_ADDITIONAL_ARGS` env var (e.g., tool use, memory tuning).
- **Predictive models**: `extraArgs` items are appended as container CLI arguments.
- **Both**: `extraEnv` adds arbitrary environment variables in standard Kubernetes format.

### TrustyAI Monitoring

Models can enable TrustyAI for bias and data drift monitoring by setting `trustyai.enabled: true`.
This deploys a `TrustyAIService` CR and the required `kserve-logger-ca-bundle` ConfigMap in the model's namespace.
Supports PVC or DATABASE storage backends.

### HuggingFace Token Authentication

Models using `hf://` URIs that are gated or private require a HuggingFace token.
Set `hfToken` at deploy time (`--set hfToken=$(cat .hf_token)`) to create an `hf-secret` Secret
and inject `HF_TOKEN` into the model container via `secretKeyRef`, following KServe's recommended approach.
The `.hf_token` file (git-ignored) holds the raw token value. See `.hf_token.example`.

### Model Source Options

The chart supports multiple methods for loading models:

- **OCI Registry (ModelCar)** - Pull models from OCI-compliant registries using ModelCar format
- **S3-compatible storage** - Load models from S3 buckets (AWS S3, MinIO, Ceph, etc.)
- **PVC (Persistent Volume Claims)** - Use models stored on persistent volumes
- **HuggingFace** - Pull models directly from HuggingFace Hub (use `hfToken` for gated models)

## Repository Structure

```
chart/
  Chart.yaml
  values.yaml                          # Generative defaults and schema
  values-<model>.yaml                  # Per-model overrides (next to values.yaml)
  templates/
    inferenceservice.yaml              # Predictive: InferenceService
    llminferenceservice.yaml           # Generative: LLMInferenceService
    servingruntime.yaml                # Predictive: ServingRuntime
    trustyai-service.yaml              # Optional: TrustyAI monitoring
    secret-hf-token.yaml               # Optional: HuggingFace token secret
    namespace.yaml
    rbac.yaml
    secret-connection.yaml
```

Each serving scenario includes:
- **rhoai-serving Helm chart** - Unified chart with model files for different scenarios
- **ArgoCD Application manifests** - GitOps applications that reference the Helm chart for one-click deployment

The structure prioritizes ease of deployment and long-term maintenance, allowing users to either:
- Deploy directly using Helm
- Use GitOps workflows with the provided ArgoCD Applications for automated deployment and lifecycle management
