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
{{- .Values.namespace.displayName | default .Values.namespace.name -}}
{{- end }}

{{/*
True if resources.limits or resources.requests include nvidia.com/gpu with a non-zero value.
GPU scheduling is driven by these requests plus HardwareProfile / Kueue (no serving.gpu flag).
*/}}
{{- define "rhoai-serving.hasNvidiaGpu" -}}
{{- $k := "nvidia.com/gpu" -}}
{{- $lim := .Values.resources.limits | default dict -}}
{{- $req := .Values.resources.requests | default dict -}}
{{- $v := "" -}}
{{- if hasKey $lim $k }}{{- $v = index $lim $k | toString | trim -}}{{- end -}}
{{- $w := "" -}}
{{- if hasKey $req $k }}{{- $w = index $req $k | toString | trim -}}{{- end -}}
{{- if or (and $v (ne $v "0")) (and $w (ne $w "0")) }}true{{- else }}false{{- end -}}
{{- end -}}

{{/*
KServe model container resources (generative LLMInferenceService + predictive InferenceService).
Strip nvidia.com/gpu from limits/requests when neither side requests a GPU, so Helm deep-merge
against GPU defaults does not leave stale GPU keys on CPU-only overlays.
*/}}
{{- define "rhoai-serving.kserveModelResources" -}}
{{- if eq (include "rhoai-serving.hasNvidiaGpu" . | trim) "true" -}}
{{- toYaml .Values.resources -}}
{{- else -}}
limits:
  {{- omit (default dict .Values.resources.limits) "nvidia.com/gpu" | toYaml | nindent 2 }}
requests:
  {{- omit (default dict .Values.resources.requests) "nvidia.com/gpu" | toYaml | nindent 2 }}
{{- end -}}
{{- end -}}
