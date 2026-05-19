#!/bin/bash
# Shared helpers for NeMo guardrails test scripts.
#
# DEPLOYMENT_NAME — chart values `name` / LLMInferenceService metadata.name
#                   (routes, secrets, labels: ${DEPLOYMENT_NAME}-nemo-guardrails)
# MODEL_NAME      — OpenAI API model id (LLMInferenceService spec.model.name),
#                   e.g. RedHatAI/gpt-oss-20b

resolve_api_model_name() {
  local deployment_name=$1
  local namespace=$2
  local override=${3:-}

  if [[ -n "${override}" ]]; then
    echo "${override}"
    return 0
  fi

  local model
  model=$(oc get LLMInferenceService "${deployment_name}" -n "${namespace}" \
    -o jsonpath='{.spec.model.name}' 2>/dev/null || true)
  if [[ -n "${model}" ]]; then
    echo "${model}"
    return 0
  fi

  echo "Warning: could not read spec.model.name for LLMInferenceService '${deployment_name}' in '${namespace}'; using deployment name as model id." >&2
  echo "${deployment_name}"
}
