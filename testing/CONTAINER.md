# Containerized k6 Testing Guide

Run k6 load tests without local installation using containers and OpenShift Jobs.

---

## Official Image

**Container Image**: `docker.io/grafana/k6:latest`  
**Registry**: [Docker Hub - grafana/k6](https://hub.docker.com/r/grafana/k6)  
**Security**: Non-root user (UID 12345), minimal attack surface

---

## Quick Start

### Local Container (Podman/Docker)

```bash
cd testing

# HPA test
./run-k6-container-hpa.sh

# KEDA test
./run-k6-container-keda.sh

# With custom model
MODEL=my-model NAMESPACE=my-namespace ./run-k6-container-hpa.sh
```

### OpenShift Job (Cloud-Native)

```bash
cd testing

# HPA test
./run-k6-job-hpa.sh

# KEDA test
./run-k6-job-keda.sh

# With custom model
MODEL=my-model NAMESPACE=my-namespace ./run-k6-job-hpa.sh
```

---

## Architecture

### Local Container Approach

```
┌─────────────────────────────────────┐
│ Podman/Docker Host                  │
│                                     │
│  ┌────────────────────────────────┐ │
│  │ grafana/k6 Container           │ │
│  │                                │ │
│  │  k6 run /scripts/hpa-test.js  │ │
│  │                                │ │
│  │  Environment:                  │ │
│  │  - MODEL=distilbert           │ │
│  │  - ROUTE_URL=model.example... │ │
│  │  - TOKEN=sha256~...           │ │
│  │                                │ │
│  │  Volume Mount:                 │ │
│  │  ./k6-scripts → /scripts:ro   │ │
│  └────────────────────────────────┘ │
└─────────────────────────────────────┘
         │
         ↓
    OpenShift Route → InferenceService
```

### OpenShift Job Approach

```
┌───────────────────────────────────────────────────┐
│ OpenShift Cluster                                 │
│                                                   │
│  ┌──────────────────────────────────────────────┐ │
│  │ ConfigMap: k6-test-scripts                   │ │
│  │  - hpa-test.js                               │ │
│  │  - keda-test.js                              │ │
│  └──────────────────────────────────────────────┘ │
│                    ↓                              │
│  ┌──────────────────────────────────────────────┐ │
│  │ Job: k6-hpa-test                             │ │
│  │                                              │ │
│  │  Pod:                                        │ │
│  │  ┌────────────────────────────────────────┐  │ │
│  │  │ Container: grafana/k6                  │  │ │
│  │  │                                        │  │ │
│  │  │  k6 run /scripts/hpa-test.js          │  │ │
│  │  │                                        │  │ │
│  │  │  Volume Mounts:                        │  │ │
│  │  │  - ConfigMap → /scripts                │  │ │
│  │  │  - Secret → TOKEN env var              │  │ │
│  │  │                                        │  │ │
│  │  │  Security:                             │  │ │
│  │  │  - runAsNonRoot: true                  │  │ │
│  │  │  - allowPrivilegeEscalation: false     │  │ │
│  │  │  - capabilities: drop ALL              │  │ │
│  │  │  - resources.limits.cpu: 1             │  │ │
│  │  │  - resources.limits.memory: 512Mi      │  │ │
│  │  └────────────────────────────────────────┘  │ │
│  └──────────────────────────────────────────────┘ │
│                    ↓                              │
│           OpenShift Route → InferenceService      │
└───────────────────────────────────────────────────┘
```

---

## File Structure

```
testing/
├── k6-scripts/                    # k6 JavaScript test scripts
│   ├── hpa-test.js               # HPA autoscaling test
│   └── keda-test.js              # KEDA autoscaling test
│
├── manifests/                     # OpenShift/Kubernetes manifests
│   ├── configmap-k6-scripts.yaml # ConfigMap with test scripts
│   ├── job-k6-hpa.yaml           # Job for HPA testing
│   └── job-k6-keda.yaml          # Job for KEDA testing
│
├── run-k6-container-hpa.sh       # Run HPA test in local container
├── run-k6-container-keda.sh      # Run KEDA test in local container
├── run-k6-job-hpa.sh             # Run HPA test as OpenShift Job
└── run-k6-job-keda.sh            # Run KEDA test as OpenShift Job
```

---

## OpenShift Best Practices

### Security

✅ **Non-root user**: k6 image runs as UID 12345 (non-root)  
✅ **Read-only volumes**: Scripts mounted as `:ro`  
✅ **Dropped capabilities**: All Linux capabilities dropped  
✅ **No privilege escalation**: `allowPrivilegeEscalation: false`  
✅ **Seccomp profile**: Uses `RuntimeDefault`  
✅ **Resource limits**: CPU and memory limits enforced

### Resource Management

```yaml
resources:
  requests:
    cpu: 100m        # Minimal baseline
    memory: 128Mi
  limits:
    cpu: "1"         # Prevent CPU hogging
    memory: 512Mi    # Prevent OOM
```

### Cleanup

Jobs auto-delete after completion:
```yaml
ttlSecondsAfterFinished: 600  # Delete after 10 minutes
```

Manual cleanup:
```bash
oc delete job k6-hpa-test -n <namespace>
oc delete job k6-keda-test -n <namespace>
```

---

## Customization

### Change k6 Test Duration

Edit `k6-scripts/hpa-test.js`:
```javascript
stages: [
  { duration: '1m', target: 30 },    // Change durations
  { duration: '5m', target: 30 },    // Extend sustain phase
]
```

Then re-create ConfigMap:
```bash
oc apply -f manifests/configmap-k6-scripts.yaml
```

### Change Virtual Users

Edit stages to adjust concurrent load:
```javascript
stages: [
  { duration: '30s', target: 100 },  // More aggressive ramp
]
```

### Add Custom Metrics

Edit `k6-scripts/hpa-test.js`:
```javascript
import { Trend } from 'k6/metrics';
const myMetric = new Trend('my_custom_metric');

export default function () {
  myMetric.add(response.timings.duration);
}
```

---

## Troubleshooting

### Job Fails to Start

```bash
# Check Job status
oc describe job k6-hpa-test -n <namespace>

# Check Pod logs
oc logs -f job/k6-hpa-test -n <namespace>
```

### Authentication Errors

```bash
# Verify token secret
oc get secret k6-test-token -n <namespace> -o yaml

# Recreate token
TOKEN=$(oc whoami -t)
oc create secret generic k6-test-token \
  --from-literal=token="${TOKEN}" \
  -n <namespace> --dry-run=client -o yaml | oc apply -f -
```

### ConfigMap Not Updated

```bash
# Delete and recreate
oc delete configmap k6-test-scripts -n <namespace>
oc apply -f manifests/configmap-k6-scripts.yaml -n <namespace>

# Restart Job
oc delete job k6-hpa-test -n <namespace>
./run-k6-job-hpa.sh
```

---

## Advantages of Containerized Approach

| Benefit | Local Container | OpenShift Job |
|---------|----------------|---------------|
| **No local install** | ✓ | ✓ |
| **Reproducible** | ✓ | ✓ |
| **CI/CD ready** | ~ | ✓ |
| **Resource limits** | Manual | ✓ Enforced |
| **Cloud-native** | ~ | ✓ |
| **Audit logs** | ~ | ✓ |
| **Access control** | ~ | ✓ RBAC |

**Use local container when:**
- Quick iteration during development
- Testing script changes rapidly
- No OpenShift cluster access

**Use OpenShift Job when:**
- Production testing
- CI/CD integration
- Need audit trail
- Multi-user environment
- Resource quotas required

---

## References

- **Official k6 Image**: https://hub.docker.com/r/grafana/k6
- **k6 Documentation**: https://k6.io/docs/
- **OpenShift Jobs**: https://docs.openshift.com/container-platform/latest/nodes/jobs/
- **ConfigMaps**: https://docs.openshift.com/container-platform/latest/nodes/pods/nodes-pods-configmaps.html
