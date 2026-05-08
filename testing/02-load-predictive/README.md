# Load Testing for Predictive Models

Test autoscaling (HPA or KEDA) with k6 load tests.

## Quick Start

```bash
# From repo root - auto-detects HPA/KEDA mode
./testing/02-load-predictive/run-k6.sh

# Monitor scaling
watch -n 2 'oc get hpa,scaledobject,pods -n model-distilbert'
```

## Custom Model

```bash
MODEL=my-model NAMESPACE=my-namespace ./testing/02-load-predictive/run-k6.sh
```

## Requirements

- `podman` or `docker` installed
- OpenShift cluster access (`oc` configured)
- Model deployed with route

## Scaling Modes

**HPA** (CPU-based): 25 VUs for 3 minutes, targets 70% CPU  
**KEDA** (request rate): 20 VUs for 5 minutes, targets 10 req/s average

## Legacy Scripts

- `run-k6-container-hpa.sh` / `run-k6-container-keda.sh` - Old separate scripts
- `run-k6-job-*.sh` - Run as OpenShift Job
- `test-k6-*.sh` - Local k6 (requires install)
- `test-vegeta.sh` - Alternative tool
