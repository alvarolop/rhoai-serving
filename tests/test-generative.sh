#!/bin/bash

NAMESPACE=${1:-model-gpt-oss}
REQUESTED=${2:-gpt-oss-20b}

# Second argument must be the LLMInferenceService metadata.name (chart values `name`, e.g. qwen3-8b), not the Helm release name (qwen).
resolve_service_name() {
  local ns=$1
  local requested=$2

  if oc get LLMInferenceService "${requested}" -n "${ns}" &>/dev/null; then
    echo "${requested}"
    return 0
  fi

  mapfile -t found < <(oc get llminferenceservice -n "${ns}" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null)
  # Drop empty lines
  local names=()
  local n
  for n in "${found[@]}"; do
    [[ -n "${n}" ]] && names+=("${n}")
  done

  if [[ ${#names[@]} -eq 0 ]]; then
    echo "No LLMInferenceService in namespace '${ns}'. Deploy first, then run:" >&2
    echo "  oc get llminferenceservice -n ${ns}" >&2
    return 1
  fi

  if [[ ${#names[@]} -eq 1 ]]; then
    echo "Note: '${requested}' not found; using the only LLMInferenceService in ${ns}: ${names[0]}" >&2
    echo "${names[0]}"
    return 0
  fi

  echo "LLMInferenceService '${requested}' not found in '${ns}'." >&2
  echo "Available names (use the chart values \`name\`, not the Helm release name):" >&2
  printf '  %s\n' "${names[@]}" >&2
  echo "Example: $0 ${ns} qwen3-8b" >&2
  return 1
}

SERVICE_NAME=$(resolve_service_name "${NAMESPACE}" "${REQUESTED}") || exit 1

# OpenAI-compatible APIs expect the served model id (vLLM), which matches LLMInferenceService spec.model.name — not the CR metadata.name.
API_MODEL=${3:-$(oc get LLMInferenceService "${SERVICE_NAME}" -n "${NAMESPACE}" -o jsonpath='{.spec.model.name}')}

if [[ -z "${API_MODEL}" ]]; then
  echo "Could not read spec.model.name from LLMInferenceService '${SERVICE_NAME}'." >&2
  echo "Pass the OpenAI model id as the third argument:" >&2
  echo "  $0 <namespace> <llmis-name> [<openai-model-id>]" >&2
  exit 1
fi

ROUTE=$(oc get LLMInferenceService "${SERVICE_NAME}" -n "${NAMESPACE}" --template='{{ .status.url }}')
TOKEN=$(oc get secret "${SERVICE_NAME}-sa-token" -n "${NAMESPACE}" -o jsonpath='{.data.token}' | base64 -d)

echo "Testing LLMInferenceService ${SERVICE_NAME} in ${NAMESPACE} (OpenAI model: ${API_MODEL})..."
echo "Route: $ROUTE"
echo "Token: ${TOKEN:0:10}..."

PAYLOAD=$(jq -n \
  --arg model "${API_MODEL}" \
  '{model: $model, messages: [{role: "user", content: "Hello, how are you?"}]}')

RESPONSE=$(curl -s -k -X POST "${ROUTE}/v1/chat/completions" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "${PAYLOAD}")

echo "Response:"
echo "${RESPONSE}" | jq .
