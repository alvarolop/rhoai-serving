#!/bin/bash
# 2/4 Creates a MaaS API key in a tenant and prints the variables to use it (OPENAI_API_URL, OPENAI_API_KEY).
#
#   eval "$(maas/2-api-key.sh --model granite-3-3-2b-instruct)"                       # default tenant (models-as-a-service)
#   eval "$(maas/2-api-key.sh --tenant maas-keycloak --model tinyllama-1b,facebook-opt-125m-simulated --expires 1d)"
#   eval "$(maas/2-api-key.sh --tenant maas-keycloak --subscription all-models)"
#
# Options:
#   -t, --tenant NAME|NAMESPACE   AITenant (name or namespace). Default: models-as-a-service
#   -s, --subscription NAME       MaaSSubscription of the tenant. Default: the highest-priority one that includes ALL the --model
#                                 names (a key is bound to ONE subscription), or the highest-priority one of the tenant
#   -m, --model M[,M2,...]        MaaSModelRef names (only used to pick the subscription and to check them)
#   -e, --expires DURATION        Default 90d
# Authentication: the OpenShift token of `oc whoami -t`. A tenant that signs in with OIDC (maas-keycloak) needs a token of its
# provider: export TOKEN=<access token>. You must belong to one of the owner groups of the subscription. The key is shown only
# once; revoke it with DELETE /maas-api/v1/api-keys/<id> or from the dashboard. Previous step: maas/1-subscriptions.sh.

set -euo pipefail

TENANT=models-as-a-service; SUBSCRIPTION=""; MODELS=""; EXPIRES_IN=90d
while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--tenant) TENANT="$2"; shift 2 ;;
        -s|--subscription) SUBSCRIPTION="$2"; shift 2 ;;
        -m|--model|--models) MODELS="$2"; shift 2 ;;
        -e|--expires) EXPIRES_IN="$2"; shift 2 ;;
        -h|--help) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "❌ Unknown option $1 (see --help)" >&2; exit 1 ;;
    esac
done

oc whoami &> /dev/null || { echo "❌ You are not logged in. Please log in and run the script again." >&2; exit 1; }

AIT=$(oc get aitenant -A -o json | jq -c --arg t "$TENANT" '[.items[] | select(.metadata.name == $t or .status.tenantNamespace == $t)][0] // empty')
[[ -n "$AIT" ]] || { echo "❌ '$TENANT' is neither an AITenant nor the namespace of one." >&2; exit 1; }
NS=$(jq -r .status.tenantNamespace <<< "$AIT"); GW=$(jq -r '.spec.gateway.name // .metadata.name' <<< "$AIT")
HOST=$(oc get route -n openshift-ingress -l gateway.networking.k8s.io/gateway-name="$GW" -o jsonpath='{.items[0].spec.host}')
[[ -n "$HOST" ]] || { echo "❌ No Route for the gateway $GW in openshift-ingress." >&2; exit 1; }
TOKEN="${TOKEN:-$(oc whoami -t)}"

if [[ -z "$SUBSCRIPTION" ]]; then
    SUBSCRIPTION=$(oc get maassubscription -n "$NS" -o json | jq -r --arg m "$MODELS" '
        ($m | split(",") | map(select(. != ""))) as $want
        | [.items[] | select(. as $s | all($want[]; . as $w | any($s.spec.modelRefs[]; .name == $w)))]
        | sort_by(-(.spec.priority // 0)) | .[0].metadata.name // empty')
    [[ -n "$SUBSCRIPTION" ]] || { echo "❌ No MaaSSubscription in $NS includes ${MODELS:-any model}. Run maas/1-subscriptions.sh $TENANT first." >&2; exit 1; }
fi

RESPONSE=$(curl -sS -X POST "https://$HOST/maas-api/v1/api-keys" \
    -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
    -d "$(jq -n --arg name "$NS-$(date +%Y%m%d-%H%M%S)" --arg sub "$SUBSCRIPTION" --arg exp "$EXPIRES_IN" \
        '{name: $name, description: "Created by maas/2-api-key.sh", subscription: $sub, expiresIn: $exp}')")

API_KEY=$(jq -r '.key // empty' <<< "$RESPONSE")
[[ -n "$API_KEY" ]] || { echo "❌ Could not create the API key: $RESPONSE" >&2; exit 1; }

VISIBLE=$(curl -sS "https://$HOST/v1/models" -H "Authorization: Bearer $API_KEY" | jq -r '[.data[]?.id] | join(", ")' 2>/dev/null || true)
echo "✅ API key created (id: $(jq -r .id <<< "$RESPONSE"), tenant: $NS, subscription: $SUBSCRIPTION, expires in: $EXPIRES_IN)" >&2
echo "   Models of the key (alias): ${VISIBLE:-none yet}" >&2
# /v1/models lists the model alias (status.resolvedModelAlias of the MaaSModelRef), not the MaaSModelRef name
for m in ${MODELS//,/ }; do
    ALIAS=$(oc get maasmodelref "$m" -n "$NS" -o jsonpath='{.status.resolvedModelAlias}' 2>/dev/null || true)
    [[ -n "$ALIAS" ]] && grep -qF "$ALIAS" <<< "$VISIBLE" || echo "⚠️  $m is not in the list of the key (no such MaaSModelRef in $NS, not Ready, or not in the subscription)" >&2
done
echo "export OPENAI_API_URL=https://$HOST/v1"
echo "export OPENAI_API_KEY=$API_KEY"
