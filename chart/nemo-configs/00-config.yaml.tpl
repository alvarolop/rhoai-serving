models:
  - type: main
    engine: openai
    model: {{ .Values.model.name }}
    api_key_env_var: OPENAI_API_KEY
    parameters:
      openai_api_base: {{ .modelUrl }}
{{- if .Values.guardrails.otel.enabled }}
# OpenTelemetry Tracing
tracing:
  enabled: true
  adapters:
    - name: OpenTelemetry
{{- end }}
{{ .Values.guardrails.config | nindent 0 }}
