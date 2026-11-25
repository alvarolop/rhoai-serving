# 011 — MaaS scripts: subscriptions, API keys and tests

Four numbered scripts in `maas/`, to run in order against the cluster you are logged into. Platform side (gateways, Routes, certificates) lives in rhoai-gitops, `docs/maas-gateway.md`.

| Script | What it does |
|---|---|
| `maas/1-subscriptions.sh [tenant ...]` | One `MaaSSubscription` + one `MaaSAuthPolicy` per tenant, covering all its models |
| `maas/2-api-key.sh [--tenant T] [--subscription S] [--model M,M2]` | Creates an API key and prints `OPENAI_API_URL` / `OPENAI_API_KEY` |
| `maas/3-test.sh [tenant ...]` | Checks gateway, Route, certificate, `maas-api`, dashboard. No request to a model |
| `maas/4-test-inference.sh [tenant ...]` | Sends one real message per tenant, through its `all-models` subscription, to a Ready model that is not a simulator |

A **tenant** is an `AITenant` (`models-as-a-service`, `maas-keycloak`, ...). Every script accepts its name or its namespace (`ai-tenant-maas-keycloak`).

## Why subscriptions

A model published in MaaS (`serving.maas.enabled`, the default for generative models) creates a `MaaSModelRef`. It stays `Pending` until a `MaaSSubscription` and a `MaaSAuthPolicy` include it, even when the pods are healthy:

```
$ oc get maasmodelref -n models-as-a-service
granite-3-3-2b-instruct   Pending
  GovernanceAttached=False  NoPairingFound  "No active subscription and auth policy pairing found"
  RuntimeReady=True         RuntimeHealthy  "Backend is healthy"
```

rhoai-gitops only ships the demo simulator with its two subscriptions. The access to the models of this repo is generated here.

## 1. `1-subscriptions.sh`

Creates `all-models` and `all-models-policy` in the namespace of each tenant, covering every `MaaSModelRef` of it with the same token limit. Rerun it after deploying or deleting a model: it updates the same two resources (`oc apply`), so the new model joins and a deleted one leaves.

```bash
maas/1-subscriptions.sh                            # every tenant
maas/1-subscriptions.sh maas-keycloak              # one tenant, by name ...
maas/1-subscriptions.sh ai-tenant-maas-keycloak    # ... or by namespace (several can be given)
maas/1-subscriptions.sh --dry-run                  # server-side validation, applies nothing
EXCLUDE=facebook-opt-125m-simulated maas/1-subscriptions.sh
LIMIT=50000 WINDOW=1m GROUPS_LIST=cluster-admins,team-a maas/1-subscriptions.sh models-as-a-service
```

| Variable | Default | Meaning |
|---|---|---|
| `NAME` | `all-models` | Name of the subscription (the policy is `<name>-policy`) |
| `LIMIT`, `WINDOW` | `100000`, `1h` | Token limit of every model (prompt + completion tokens). The CRD requires one per model |
| `GROUPS_LIST` | `system:authenticated` | Owner groups, comma separated. In a Keycloak tenant they must be the names in the `groups` claim of the token |
| `PRIORITY` | `0` | Picks the default subscription when a user matches several (production 100, staging 50, development 0, sandbox -10) |
| `EXCLUDE` | empty | `MaaSModelRef` names that keep their own subscription, such as the demo simulator. A model in two subscriptions makes the API-key subscription choice ambiguous |

- **A subscription never crosses tenants.** Each tenant has its own `maas-api` (it only reads the subscriptions of its namespace, `MAAS_SUBSCRIPTION_NAMESPACE`) and its own gateway-scoped `AuthPolicy`. The CRD would accept a `modelRefs[].namespace` of another tenant, but that is not how a tenant is isolated. A model that must be in both tenants is deployed twice (`serving.maas.tenant`) and each tenant gets its own subscription.
- Tenants without `MaaSModelRef` are skipped.
- The result is not in git (the Argo CD applications of rhoai-gitops use `prune: false`).
- The policy stays `Pending` while the gateway `AuthPolicy` is enforced again; it can take longer if the Kuadrant operator is restarting.

## 2. `2-api-key.sh`

Creates an API key in a tenant and prints the variables to use it. A key is bound to **one** subscription, so the model list only picks it (and is checked at the end).

```bash
eval "$(maas/2-api-key.sh --model granite-3-3-2b-instruct)"                                   # default tenant
eval "$(maas/2-api-key.sh --tenant maas-keycloak --model tinyllama-1b,facebook-opt-125m-simulated --expires 1d)"
eval "$(maas/2-api-key.sh --tenant maas-keycloak --subscription all-models)"
curl -s $OPENAI_API_URL/models -H "Authorization: Bearer $OPENAI_API_KEY"
```

| Option | Default | Meaning |
|---|---|---|
| `-t, --tenant` | `models-as-a-service` | AITenant name or namespace |
| `-s, --subscription` | highest priority that includes **all** `--model` names, else the highest of the tenant | MaaSSubscription of the tenant |
| `-m, --model` | none | MaaSModelRef names, comma separated |
| `-e, --expires` | `90d` | Key lifetime |

It authenticates with `oc whoami -t`. A tenant with OIDC (`maas-keycloak`) needs a token of its provider: `export TOKEN=<access token>`. You must belong to one of the owner groups of the subscription. The key is shown once; revoke it with `DELETE /maas-api/v1/api-keys/<id>` or from the dashboard. It prints the models the key can see and warns when one of `--model` is missing.

## 3. `3-test.sh`

Read only: it never calls a model. It loops over every `AITenant` (or the ones you name), so a new tenant is covered without changing the script. Exit code 1 if any check fails.

```bash
maas/3-test.sh                # every tenant
maas/3-test.sh maas-keycloak  # one tenant, by name or namespace
```

| Check | What it proves | If it fails |
|---|---|---|
| Gateway and listeners Programmed | The controller accepted both listeners (same port, different hostname) | `oc describe gateway <name> -n openshift-ingress`: conflicts, missing certificate Secret |
| A listener has a hostname | `/v1/tenants` can build the external URL | Set the hostname of the public listener |
| Listener without hostname | The internal address of the models answers | Restore `https-internal` |
| Route is passthrough, same host as the listener | The router forwards the SNI the listener expects | A `reencrypt` Route against a hostname listener gives HTTP 503 |
| Certificate trusted and valid for the host | The users get the Let's Encrypt wildcard, not a self-signed one | `tlsSecret` points at the wrong secret |
| `/maas-api/health` 200 **ten times** | Every gateway pod serves the route | A 503 only from one pod: see below |
| `/v1/tenants` 200 with the right `externalUrl` | `maas-api` resolves the gateway | 500 `Failed to resolve gateway`: the listener has no hostname. 401/403: the tenant needs its own (OIDC) token, reported as a warning |
| Internal address answers 200 (from a pod) | In-cluster clients of the model addresses work | No listener without hostname, or its service CA certificate is missing |
| `maas-ui` log, dashboard `/maas/api/v1/models` | The dashboard finds and reaches MaaS | `oc rollout restart deploy/maas-ui -n redhat-ods-applications` forces a new discovery |

**A gateway pod that answers 503 to everything** (seen on this cluster): the log shows `wasm_fail_stream` and `Plugin kuadrant-wasm-shim failed to load` / `configured to fail closed`. A new gateway pod (the HPA adds one) downloads the Kuadrant wasm plugin from `http://kuadrant-operator-wasm.kuadrant-system.svc:8082` at start; if the Kuadrant operator is down at that moment (it restarts when the control plane is slow), the plugin never loads and that pod fails closed for good, so about half of the calls fail. Delete that pod: the new one fetches the plugin again.

```bash
oc get pods -n openshift-ingress | grep maas
oc logs -n openshift-ingress <gateway-pod> | grep "failed to load"
oc delete pod -n openshift-ingress <gateway-pod>
```

## 4. `4-test-inference.sh`

Sends one real message (`Say hi`) **per tenant**, through its widest subscription (the one `1-subscriptions.sh` creates, `all-models`; `NAME=<name>` if you used another) to the first `Ready` model that is not a simulator. It creates a 1 h key bound to that subscription and revokes it afterwards.

```bash
maas/4-test-inference.sh                   # every tenant
maas/4-test-inference.sh maas-keycloak
TOKEN_OVERRIDE=<access token> maas/4-test-inference.sh maas-keycloak   # an OIDC tenant that refuses the OpenShift token
```

- It prints the request (URL, masked key, subscription, JSON body, MaaSModelRef and alias) and the response (HTTP code and latency, the answer, finish reason, token usage and the raw JSON), so you can see what went through the gateway. `max_tokens` is 8, so `Finish: length` is normal.
- Simulators (`llm-d-inference-sim`) are skipped: they answer anything and say nothing about the real serving path.
- A tenant without the subscription, or without a Ready real model, is a **warning** (nothing to send), not a failure. Run `1-subscriptions.sh` first.
- It proves that key creation, Authorino, the subscription, the rate limit and the model route work end to end for a real model. When it fails, check the `AuthPolicy`, the subscription and the `LLMInferenceService`.
- It needs a Ready model: with no GPU node, GPU models are skipped. CPU models (`granite-3-3-2b-instruct`, `tinyllama-1b`) are enough.
