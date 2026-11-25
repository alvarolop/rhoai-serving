#!/bin/bash
# 4/4 Sends one real message ("Say hi") per MaaS tenant, through its widest subscription (the one of maas/1-subscriptions.sh,
# NAME, default all-models), to the first Ready model that is not a simulator. It creates a 1 h API key bound to that subscription
# and revokes it afterwards.
#
#   maas/4-test-inference.sh                  # every tenant (AITenant)
#   maas/4-test-inference.sh maas-keycloak    # only these tenants (AITenant name or namespace)
#   TOKEN_OVERRIDE=<access token> maas/4-test-inference.sh maas-keycloak   # an OIDC tenant that refuses the OpenShift token
#
# Simulators (llm-d-inference-sim) are skipped: they answer anything and say nothing about the real serving path. A tenant without
# the subscription, or without a Ready real model, is a warning. Previous step: maas/3-test.sh (gateway, Route, certificate).
# See docs/011-maas.md. Needs: oc (logged in), curl, jq.

set -uo pipefail

ONLY=("$@")
SUBNAME="${NAME:-all-models}"
FAILS=0
ok()   { echo "  ✅ $*"; }
bad()  { echo "  ❌ $*"; FAILS=$((FAILS+1)); }
warn() { echo "  ⚠️  $*"; }

oc whoami &> /dev/null || { echo "❌ You are not logged in. Please log in and run the script again." >&2; exit 1; }
AUTH="${TOKEN_OVERRIDE:-$(oc whoami -t)}"

AITENANTS=$(oc get aitenant -A -o json)
if [[ ${#ONLY[@]} -gt 0 ]]; then
    SEL=$(printf '%s\n' "${ONLY[@]}" | jq -R . | jq -sc .)
    LIST=$(jq -r --argjson sel "$SEL" '.items[] | select((.metadata.name as $n | .status.tenantNamespace as $ns | $sel | (index($n) or index($ns)))) | "\(.metadata.name)|\(.status.tenantNamespace)|\(.spec.gateway.name // .metadata.name)"' <<< "$AITENANTS")
    [[ -n "$LIST" ]] || { echo "❌ No AITenant matches: ${ONLY[*]}" >&2; exit 1; }
else
    LIST=$(jq -r '.items[] | "\(.metadata.name)|\(.status.tenantNamespace)|\(.spec.gateway.name // .metadata.name)"' <<< "$AITENANTS")
fi

for T in $LIST; do
    IFS='|' read -r TNAME TNS GW <<< "$T"
    echo "== Tenant $TNAME (subscription $SUBNAME)"
    RHOST=$(oc get route -n openshift-ingress -l gateway.networking.k8s.io/gateway-name="$GW" -o jsonpath='{.items[0].spec.host}')
    [[ -n "$RHOST" ]] || { bad "No Route for the gateway $GW"; continue; }
    SUB=$(oc get maassubscription "$SUBNAME" -n "$TNS" -o json 2>/dev/null) || { warn "No subscription $SUBNAME in $TNS: run maas/1-subscriptions.sh $TNAME"; continue; }

    MODEL=$(oc get llminferenceservice -n "$TNS" -o json | jq -r --argjson sub "$SUB" '
        [.items[] | select(([.status.conditions[]?|select(.type=="Ready")|.status][0]=="True")
                           and (([.spec.template.containers[]?.image] | map(test("inference-sim")) | any) | not))
                  | .metadata.name | select(. as $m | $sub.spec.modelRefs | any(.name == $m))][0] // empty')
    if [[ -z "$MODEL" ]]; then warn "$SUBNAME has no Ready model that is not a simulator (nothing to send)"; continue; fi
    ALIAS=$(oc get maasmodelref "$MODEL" -n "$TNS" -o jsonpath='{.status.resolvedModelAlias}')

    KEY=$(curl -s -X POST "https://$RHOST/maas-api/v1/api-keys" -H "Authorization: Bearer $AUTH" -H "Content-Type: application/json" \
        -d "$(jq -n --arg s "$SUBNAME" --arg n "test-inference-$TNAME" '{name:$n, description:"Created by maas/4-test-inference.sh", subscription:$s, expiresIn:"1h"}')")
    SECRET=$(jq -r '.key // empty' <<< "$KEY"); KID=$(jq -r '.id // empty' <<< "$KEY")
    if [[ -z "$SECRET" ]]; then warn "Could not create the API key (an OIDC tenant may need TOKEN_OVERRIDE=<its access token>): $(head -c 120 <<< "$KEY")"; continue; fi

    BODY=$(jq -nc --arg m "$ALIAS" '{model:$m, messages:[{role:"user",content:"Say hi"}], max_tokens:8}')
    echo "  ➡️  Request:  POST https://$RHOST/v1/chat/completions"
    echo "      Headers:  Authorization: Bearer ${SECRET:0:12}…  (API key $KID, subscription $SUBNAME, expires in 1h)"
    echo "      Body:     $BODY"
    echo "      Model:    $MODEL (MaaSModelRef) = $ALIAS (alias used in the request)"
    RESULT=$(curl -s -o /tmp/maas-test-reply.json -w '%{http_code} %{time_total}' --max-time 90 "https://$RHOST/v1/chat/completions" \
        -H "Authorization: Bearer $SECRET" -H "Content-Type: application/json" -d "$BODY")
    CODE=${RESULT%% *}; SECS=${RESULT##* }
    echo "  ⬅️  Response: HTTP $CODE in ${SECS}s"
    if [[ "$CODE" == 200 ]]; then
        echo "      Answer:   \"$(jq -r '.choices[0].message.content // empty' /tmp/maas-test-reply.json | tr '\n' ' ')\""
        echo "      Finish:   $(jq -r '.choices[0].finish_reason // "n/a"' /tmp/maas-test-reply.json), served by model $(jq -r '.model // "n/a"' /tmp/maas-test-reply.json)"
        echo "      Tokens:   $(jq -r '.usage | "prompt \(.prompt_tokens), completion \(.completion_tokens), total \(.total_tokens)"' /tmp/maas-test-reply.json 2>/dev/null || echo n/a)"
        echo "      Raw:      $(jq -c . /tmp/maas-test-reply.json | cut -c1-400)"
        ok "$MODEL answered"
    else
        echo "      Raw:      $(head -c 400 /tmp/maas-test-reply.json)"
        bad "$MODEL: HTTP $CODE"
    fi
    curl -s -o /dev/null -X DELETE "https://$RHOST/maas-api/v1/api-keys/$KID" -H "Authorization: Bearer $AUTH"
done

echo
[[ $FAILS -eq 0 ]] && echo "✅ All checks passed" || { echo "❌ $FAILS check(s) failed"; exit 1; }
