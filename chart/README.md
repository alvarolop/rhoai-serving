# rhoai-serving

Production-ready Helm chart for deploying Predictive and Generative AI models on Red Hat OpenShift AI using KServe Raw deployment mode

## Generating Documentation

This chart uses [helm-docs](https://github.com/norwoodj/helm-docs) to auto-generate comprehensive documentation from `values.yaml` comments.

To generate the full README with values table:

```bash
# Install helm-docs (see HELM_DOCS.md for installation instructions)
make docs
```

See [HELM_DOCS.md](HELM_DOCS.md) for detailed setup and usage instructions.

## Quick Start

Deploy a model using the two-layer values approach:

```bash
helm template <release> . \
  -f values.yaml \
  -f values-<model>.yaml | oc apply -f -
```

Example model values files:
- **Generative (GPU)**: `values-qwen3-8b-fp8-dynamic.yaml`, `values-gpt-oss-20b.yaml`
- **Embeddings (GPU)**: `values-bge-m3.yaml`, `values-nomic-embed-text-v2-moe-gpu.yaml`
- **Predictive (CPU)**: `values-distilbert.yaml`
- **Autoscaling demo**: `values-qwen3-8b-autoscale.yaml`

## Configuration

See `values.yaml` for detailed configuration options with inline documentation.

Key configuration sections:
- **Scaling**: Static replicas or HPA/KEDA autoscaling
- **Model Source**: HuggingFace Hub, OCI ModelCar, S3, or PVC
- **Authentication**: Red Hat Connectivity Link (Authorino)
- **Monitoring**: TrustyAI for bias and drift detection
- **Health Probes**: Configurable for large models with slow startup

## Documentation

- [Chart Documentation](README.md) - Auto-generated from values.yaml (run `make docs`)
- [helm-docs Setup](HELM_DOCS.md) - Installation and usage guide
- [Repository README](../README.md) - Full repository documentation

---
**Note**: This README is a placeholder. Run `make docs` after installing helm-docs to generate the full documentation with values table.
