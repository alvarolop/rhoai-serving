models:
  - type: main
    engine: openai
    parameters:
      openai_api_base: {{ .modelUrl }}
      model_name: {{ .Values.model.name }}
{{- if .Values.guardrails.guardLlm.enabled }}
  # Guard LLM configuration for future use
  # NOTE: NeMo's built-in self-check flows have a bug where they call the main model
  # instead of the guard model. Disabled until NeMo Guardrails fixes this issue.
  # See: https://github.com/NVIDIA/NeMo-Guardrails/issues
  - type: self_check
    engine: openai
    model: {{ .guardModelName }}
    parameters:
      openai_api_base: {{ .guardUrl }}
{{- end }}
{{- if .Values.guardrails.otel.enabled }}
# OpenTelemetry Tracing
tracing:
  enabled: true
  adapters:
    - name: OpenTelemetry
{{- end }}
{{ .Values.guardrails.config | nindent 0 }}
