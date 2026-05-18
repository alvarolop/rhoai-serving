models:
  - type: main
    engine: openai
    parameters:
      openai_api_base: {{ .modelUrl }}
      model_name: {{ .Values.model.name }}
{{- if .Values.guardrails.nemo.guardLlm.enabled }}
  - type: self_check
    engine: openai
    parameters:
      openai_api_base: {{ .guardUrl }}
      model_name: {{ .guardModelName }}
{{- end }}
{{- if .Values.guardrails.nemo.otel.enabled }}
# OpenTelemetry Tracing
tracing:
  enabled: true
  adapters:
    - name: OpenTelemetry
{{- end }}
{{ .Values.guardrails.nemo.config | nindent 0 }}
