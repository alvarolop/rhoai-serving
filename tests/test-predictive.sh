#!/bin/bash

MODEL_NAME=${1:-distilbert}
NAMESPACE="model-$MODEL_NAME"

ROUTE=$(oc get route ${MODEL_NAME} -n ${NAMESPACE} --template='https://{{ .spec.host}}')
TOKEN=$(oc get secret ${MODEL_NAME}-sa-token -n ${NAMESPACE} -o jsonpath='{.data.token}' | base64 -d)

echo "Testing ${MODEL_NAME} in ${NAMESPACE}..."
echo "Route: $ROUTE"
echo "Token: ${TOKEN:0:10}..."

RESPONSE=$(curl -s -k -X POST "${ROUTE}/v2/models/${MODEL_NAME}/infer" \
-H "Authorization: Bearer $TOKEN" \
-H "Content-Type: application/json" \
-d '{ "inputs": [ { "name": "input_ids", "shape": [1, 4], "datatype": "INT64", "data": [101, 7592, 2089, 102] }, { "name": "attention_mask", "shape": [1, 4], "datatype": "INT64", "data": [1, 1, 1, 1] } ] }')

echo "Response:"
echo "${RESPONSE}" | jq .
