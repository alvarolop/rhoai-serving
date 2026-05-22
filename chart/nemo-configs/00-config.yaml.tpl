models:
  - type: main
    engine: openai
    model: {{ .Values.model.name }}
    api_key_env_var: OPENAI_API_KEY
    parameters:
      openai_api_base: {{ .modelUrl }}
{{- if .Values.guardrails.guardLlm.enabled }}
  # Guard LLM for self-check input evaluations
  - type: self_check_input
    engine: openai
    model: {{ .guardModelName }}
    api_key_env_var: GUARD_MODEL_API_KEY
    parameters:
      openai_api_base: {{ .guardUrl }}
  # Guard LLM for self-check output evaluations
  - type: self_check_output
    engine: openai
    model: {{ .guardModelName }}
    api_key_env_var: GUARD_MODEL_API_KEY
    parameters:
      openai_api_base: {{ .guardUrl }}
{{- end }}
{{ .Values.guardrails.config | nindent 0 }}
