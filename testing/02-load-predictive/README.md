# Load Testing for Predictive Models

Performance testing and autoscaling validation for predictive models (InferenceService).

## Quick Start

### Containerized k6 (Recommended)

**HPA Testing** (CPU-based autoscaling):
```bash
./testing/02-load-predictive/run-k6-container-hpa.sh
```

**KEDA Testing** (custom metrics autoscaling):
```bash
./testing/02-load-predictive/run-k6-container-keda.sh
```

**OpenShift Job** (cloud-native):
```bash
./testing/02-load-predictive/run-k6-job-hpa.sh
./testing/02-load-predictive/run-k6-job-keda.sh
```

### Alternative Tools

**Vegeta** (simple HTTP load):
```bash
./testing/02-load-predictive/test-vegeta.sh
```

**k6 Local** (requires k6 binary installed):
```bash
./testing/02-load-predictive/test-k6-hpa.sh
./testing/02-load-predictive/test-k6-keda.sh
```

## Structure

```
02-load-predictive/
├── k6-scripts/                   # k6 JavaScript test scripts
│   ├── hpa-test.js              # HPA autoscaling test
│   └── keda-test.js             # KEDA autoscaling test
│
├── manifests/                    # OpenShift Job manifests
│   ├── configmap-k6-scripts.yaml
│   ├── job-k6-hpa.yaml
│   └── job-k6-keda.yaml
│
├── run-k6-container-hpa.sh      # Podman/Docker HPA test
├── run-k6-container-keda.sh     # Podman/Docker KEDA test
├── run-k6-job-hpa.sh            # OpenShift Job HPA test
├── run-k6-job-keda.sh           # OpenShift Job KEDA test
│
├── test-k6-hpa.sh               # Legacy (local k6)
├── test-k6-keda.sh              # Legacy (local k6)
└── test-vegeta.sh               # Alternative tool
```

## Test Scenarios

### HPA (Horizontal Pod Autoscaler)
- **Trigger**: CPU utilization > 80%
- **Pattern**: Ramping virtual users (0 → 5 → 30 → 50)
- **Duration**: ~6 minutes
- **Monitors**: HPA metrics, pod count

### KEDA (Kubernetes Event Driven Autoscaling)
- **Trigger**: `ovms_current_requests` > 2
- **Pattern**: Constant 20 concurrent users
- **Duration**: 5 minutes
- **Monitors**: ScaledObject, Prometheus metrics

## Monitoring

```bash
# Watch HPA scaling
watch -n 2 'oc get hpa,pods -n model-distilbert'

# Watch KEDA scaling
watch -n 2 'oc get scaledobject,pods -n model-distilbert'

# Check Prometheus metric
oc exec -n model-distilbert <pod> -c kserve-container -- \
  curl -s localhost:8001/metrics | grep ovms_current_requests
```

## Documentation

See [../README.md](../README.md#2-performance-testing---predictive-models) for full documentation and [../CONTAINER.md](../CONTAINER.md) for containerized testing details.
