{{/*
Namespace name used by all namespaced resources.
*/}}
{{- define "rhoai-serving.namespaceName" -}}
{{- .Values.namespace.name -}}
{{- end }}

{{/*
OpenShift console display name for the Namespace (when namespace.create is true).
*/}}
{{- define "rhoai-serving.namespaceDisplayName" -}}
{{- .Values.namespace.displayName | default (printf "Model - %s" .Values.name) -}}
{{- end }}

{{/*
OpenShift console description for the Namespace (when namespace.create is true).
*/}}
{{- define "rhoai-serving.namespaceDescription" -}}
{{- .Values.namespace.description | default (printf "Serving model %s" .Values.name) -}}
{{- end }}

{{/*
True if the model container should request NVIDIA GPU resources and GPU-related chart bits
(tolerations, full resources blob). Uses resources.limits/requests nvidia.com/gpu unless
HardwareProfile is cpu-profile: cpu-profile forces CPU-only rendering and strips GPU in
kserveModelResources (Helm deep-merge can still leave stale GPU keys from another layer).
*/}}
{{- define "rhoai-serving.hasNvidiaGpu" -}}
{{- $hp := .Values.serving.hardwareProfile | default dict -}}
{{- $hpname := $hp.name | default "" | toString | trim -}}
{{- if and $hpname (eq $hpname "cpu-profile") -}}
false
{{- else -}}
{{- $k := "nvidia.com/gpu" -}}
{{- $res := .Values.mainContainer.resources | default dict -}}
{{- $lim := $res.limits | default dict -}}
{{- $req := $res.requests | default dict -}}
{{- $v := "" -}}
{{- if hasKey $lim $k }}{{- $v = index $lim $k | toString | trim -}}{{- end -}}
{{- $w := "" -}}
{{- if hasKey $req $k }}{{- $w = index $req $k | toString | trim -}}{{- end -}}
{{- if or (and $v (ne $v "0")) (and $w (ne $w "0")) }}true{{- else }}false{{- end -}}
{{- end -}}
{{- end -}}

{{/*
KServe model container resources (generative LLMInferenceService + predictive InferenceService).
Strip nvidia.com/gpu from limits/requests when neither side requests a GPU, so Helm deep-merge
does not leave stale GPU keys on CPU-only overlays.
*/}}
{{- define "rhoai-serving.kserveModelResources" -}}
{{- $res := .Values.mainContainer.resources | default dict -}}
{{- if eq (include "rhoai-serving.hasNvidiaGpu" . | trim) "true" -}}
{{- toYaml $res -}}
{{- else -}}
limits:
  {{- omit ($res.limits | default dict) "nvidia.com/gpu" | toYaml | nindent 2 }}
requests:
  {{- omit ($res.requests | default dict) "nvidia.com/gpu" | toYaml | nindent 2 }}
{{- end -}}
{{- end -}}

{{/*
OpenShift AI connections API protocol (opendatahub.io/connection-type-protocol on the Secret).

- uri: Opaque, data.URI (base64), annotations connection-type-protocol uri.
- oci: Opaque, annotations connection-type-protocol oci, data.OCI_HOST = base64(model.uri);
  optional data .dockerconfigjson when model.oci.dockerconfigjson is set (private registry).
- s3: Opaque, data AWS_* keys (base64), labels dashboard + managed, annotations connection-type + protocol + ref s3.

Protocol auto-detected from model.uri prefix: oci:// → oci, s3:// → s3, otherwise → uri.
*/}}
{{- define "rhoai-serving.modelConnectionProtocol" -}}
{{- $uri := .Values.model.uri | default "" | toString | trim -}}
{{- if hasPrefix "oci://" $uri -}}oci
{{- else if hasPrefix "s3://" $uri -}}s3
{{- else -}}uri
{{- end -}}
{{- end -}}

{{/*
Non-empty bucket path for S3 connections (opendatahub.io/connection-path). Trims slashes.
*/}}
{{- define "rhoai-serving.modelConnectionS3Path" -}}
{{- $s3 := .Values.model.s3 | default dict -}}
{{- $p := $s3.path | default "" | toString | trim -}}
{{- $p | trimPrefix "/" | trimSuffix "/" -}}
{{- end -}}

{{/*
Emit hf-secret and HF_TOKEN env only for Hugging Face Hub URIs (hf://). OCI ModelCars and other
schemes do not use this Secret even if hfToken is set by mistake.
*/}}
{{- define "rhoai-serving.useHfToken" -}}
{{- $tok := .Values.hfToken | default "" | toString | trim -}}
{{- $uri := .Values.model.uri | default "" | toString | trim -}}
{{- if and $tok (hasPrefix "hf://" $uri) -}}true
{{- else -}}false
{{- end -}}
{{- end -}}

{{/*
Kueue LocalQueue the workload is submitted to. It must match the HardwareProfile's
spec.scheduling.kueue.localQueueName, so it is derived from serving.hardwareProfile.name
(rhoai-gitops reserved-spot queues) unless kueue.localQueue is set.
  gpu-profile       -> serving-lq (ClusterQueue serving-cq)
  gpu-batch-profile -> batch-lq   (ClusterQueue batch-cq)
  cpu-profile/other -> default    (ClusterQueue cluster-queue)
*/}}
{{- define "rhoai-serving.kueueLocalQueue" -}}
{{- $hp := .Values.serving.hardwareProfile.name | default "" -}}
{{- if .Values.kueue.localQueue -}}{{ .Values.kueue.localQueue }}
{{- else if eq $hp "gpu-profile" -}}serving-lq
{{- else if eq $hp "gpu-batch-profile" -}}batch-lq
{{- else -}}default
{{- end -}}
{{- end -}}

{{/*
Kueue WorkloadPriorityClass label value. RHOAI 3.5 does not apply the HardwareProfile priorityClass to an
LLMInferenceService, so it is set on the workload itself. Derived from serving.hardwareProfile.name unless
kueue.priorityClass is set; empty means no label.
  gpu-profile       -> model-critical
  gpu-batch-profile -> batch-nightly
*/}}
{{- define "rhoai-serving.kueuePriorityClass" -}}
{{- $hp := .Values.serving.hardwareProfile.name | default "" -}}
{{- if .Values.kueue.priorityClass -}}{{ .Values.kueue.priorityClass }}
{{- else if eq $hp "gpu-profile" -}}model-critical
{{- else if eq $hp "gpu-batch-profile" -}}batch-nightly
{{- end -}}
{{- end -}}
