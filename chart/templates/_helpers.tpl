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
