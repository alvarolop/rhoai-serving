#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
: "${1:?usage: ./deploy-mode.sh chart/values-<model>.yaml [helm template args...]}"
helm template chart --generate-name -f chart/values.yaml -f "$1" "${@:2}" | oc apply -f -
