#!/bin/bash
# 3/4 Checks the exposure of the MaaS tenants (gateway + Route + certificate + maas-api + dashboard). Read only, no request to a model.
#
#   maas/3-test.sh                       # every tenant (AITenant), dashboard included
#   maas/3-test.sh maas-keycloak         # only these tenants (AITenant name or namespace)
#
# See docs/011-maas.md for what each check proves and what to do when it fails. Next: maas/4-test-inference.sh (a real message).
# Needs: oc (logged in), curl, jq, openssl.

set -uo pipefail

ONLY=("$@")
GW_NS=openshift-ingress
FAILS=0
ok()   { echo "  ✅ $*"; }
bad()  { echo "  ❌ $*"; FAILS=$((FAILS+1)); }
warn() { echo "  ⚠️  $*"; }

oc whoami &> /dev/null || { echo "❌ You are not logged in. Please log in and run the script again." >&2; exit 1; }
TOKEN=$(oc whoami -t)

# In-cluster caller used to test the internal address of the gateways (maas-ui has curl)
incluster() { oc exec -n redhat-ods-applications deploy/maas-ui -- "$@" 2>/dev/null; }

AITENANTS=$(oc get aitenant -A -o json)
if [[ ${#ONLY[@]} -gt 0 ]]; then
    SEL=$(printf '%s\n' "${ONLY[@]}" | jq -R . | jq -sc .)
    LIST=$(jq -r --argjson sel "$SEL" '.items[] | select((.metadata.name as $n | .status.tenantNamespace as $ns | $sel | (index($n) or index($ns)))) | "\(.metadata.name):\(.spec.gateway.name // .metadata.name)"' <<< "$AITENANTS")
    [[ -n "$LIST" ]] || { echo "❌ No AITenant matches: ${ONLY[*]}" >&2; exit 1; }
else
    LIST=$(jq -r '.items[] | "\(.metadata.name):\(.spec.gateway.name // .metadata.name)"' <<< "$AITENANTS")
fi

for TENANT in $LIST; do
    NAME=${TENANT%%:*}; GW=${TENANT##*:}
    echo "== Tenant $NAME (gateway $GW)"

    # 1. Gateway: Programmed, a listener with hostname (maas-api reads it in /v1/tenants) and the internal listener without it
    GWJSON=$(oc get gateway "$GW" -n $GW_NS -o json 2>/dev/null) || { bad "Gateway $GW not found in $GW_NS"; continue; }
    [[ $(jq -r '[.status.conditions[]|select(.type=="Programmed")][0].status' <<< "$GWJSON") == True ]] && ok "Gateway Programmed" || bad "Gateway not Programmed"
    HOST=$(jq -r '[.spec.listeners[].hostname // empty][0] // empty' <<< "$GWJSON")
    [[ -n "$HOST" ]] && ok "Listener with hostname: $HOST" || bad "No listener has a hostname: /v1/tenants (and the dashboard) fails with 'Unable to determine external hostname'"
    [[ $(jq '[.spec.listeners[]|select(.hostname == null)]|length' <<< "$GWJSON") -ge 1 ]] && ok "Internal listener without hostname" || warn "No listener without hostname: the in-cluster address of the models will not answer"
    NOTPROG=$(jq -r '[.status.listeners[]|select(([.conditions[]|select(.type=="Programmed")][0].status)!="True")|.name]|join(",")' <<< "$GWJSON")
    [[ -z "$NOTPROG" ]] && ok "All listeners Programmed" || bad "Listeners not Programmed: $NOTPROG"

    # 2. Route: passthrough and same host as the listener
    ROUTE=$(oc get route -n $GW_NS -l gateway.networking.k8s.io/gateway-name="$GW" -o json | jq -c '.items[0] // empty')
    if [[ -z "$ROUTE" ]]; then bad "No Route with the label gateway.networking.k8s.io/gateway-name=$GW"; continue; fi
    TERM=$(jq -r .spec.tls.termination <<< "$ROUTE"); RHOST=$(jq -r .spec.host <<< "$ROUTE")
    [[ "$TERM" == passthrough ]] && ok "Route $RHOST is passthrough" || bad "Route termination is '$TERM' (expected passthrough: reencrypt resets against a listener with hostname -> HTTP 503)"
    [[ "$RHOST" == "$HOST" ]] && ok "Route host = listener hostname" || bad "Route host ($RHOST) differs from the listener hostname ($HOST)"

    # 3. Certificate that the users get: valid for the host and trusted by the system store
    OUT=$(echo | openssl s_client -connect "$RHOST:443" -servername "$RHOST" -verify_hostname "$RHOST" 2>/dev/null)
    if grep -q "Verification: OK" <<< "$OUT"; then
        ok "Certificate trusted and valid for $RHOST ($(openssl x509 -noout -issuer <<< "$(sed -n '/BEGIN CERT/,/END CERT/p' <<< "$OUT")" | sed 's/issuer=//'))"
    else
        bad "Certificate not trusted or not valid for $RHOST: $(grep -m1 'Verification' <<< "$OUT")"
    fi

    # 4. maas-api through the Route
    # Ten calls, not one: the Service load-balances between the gateway pods, and a pod whose Kuadrant wasm plugin failed to load
    # (fail closed) answers 503 to every request it gets, so a single call can pass by luck
    CODES=$(for _ in $(seq 10); do curl -s -o /dev/null -w '%{http_code}\n' --max-time 10 "https://$RHOST/maas-api/health"; done | sort | uniq -c | awk '{printf "%s x%s ", $2, $1}')
    [[ "$CODES" == "200 x10 " ]] && ok "/maas-api/health 200 (10 of 10)" || bad "/maas-api/health, 10 calls: $CODES(a 503 from one gateway pod: its wasm plugin failed to load, delete that pod)"
    RESP=$(curl -s --max-time 10 -w '\n%{http_code}' -H "Authorization: Bearer $TOKEN" "https://$RHOST/maas-api/v1/tenants")
    CODE=${RESP##*$'\n'}; BODY=${RESP%$'\n'*}
    if [[ "$CODE" == 200 ]]; then
        EXT=$(jq -r '.tenants[0].gateway.externalUrl' <<< "$BODY")
        [[ "$EXT" == "https://$RHOST" ]] && ok "/v1/tenants 200, externalUrl $EXT" || bad "/v1/tenants externalUrl is $EXT (expected https://$RHOST)"
    elif [[ "$CODE" == 401 || "$CODE" == 403 ]]; then
        warn "/v1/tenants $CODE: this tenant does not accept the OpenShift token (OIDC tenant); test it with its own token"
    else
        bad "/v1/tenants $CODE: $(jq -r '.details // .error // .' <<< "$BODY" 2>/dev/null | head -c 200)"
    fi

    # 5. Internal address (the first URL in the status of every model): answered by the listener without hostname
    SVC=$(oc get svc -n $GW_NS -l gateway.networking.k8s.io/gateway-name="$GW" -o jsonpath='{.items[0].metadata.name}')
    if [[ -n "$SVC" ]]; then
        CODE=$(incluster curl -sk -o /dev/null -w '%{http_code}' --max-time 10 "https://$SVC.$GW_NS.svc.cluster.local/maas-api/health")
        [[ "$CODE" == 200 ]] && ok "Internal address $SVC answers 200" || bad "Internal address $SVC answers '${CODE:-no answer}' (SNI reset: the listener without hostname is missing?)"
    fi
done

# 6. maas-ui finds the API (this was the symptom: "MaaS API discovery failed; will retry")
echo "== Dashboard"
LAST=$(oc logs -n redhat-ods-applications deploy/maas-ui --since=5m 2>/dev/null | grep -E "discovery failed|discovered" | tail -1)
if grep -q "discovery failed" <<< "$LAST"; then bad "maas-ui: $(cut -c1-200 <<< "$LAST")"
elif [[ -n "$LAST" ]]; then ok "maas-ui discovered the API"
else warn "maas-ui logged neither discovery nor failure in the last 5 minutes (already discovered; restart it to force a new discovery)"; fi

DASH=$(oc get route rh-ai -n $GW_NS -o jsonpath='{.spec.host}' 2>/dev/null || oc get route data-science-gateway -n $GW_NS -o jsonpath='{.spec.host}')
CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 -H "Authorization: Bearer $TOKEN" "https://$DASH/maas/api/v1/models")
[[ "$CODE" == 200 ]] && ok "Dashboard backend /maas/api/v1/models 200" || bad "Dashboard backend /maas/api/v1/models $CODE"

echo
[[ $FAILS -eq 0 ]] && echo "✅ All checks passed" || { echo "❌ $FAILS check(s) failed"; exit 1; }
