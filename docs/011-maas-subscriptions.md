# MaaS subscriptions and API keys for the models

A model published in Models-as-a-Service (`serving.maas.enabled`, the default for generative models) creates a `MaaSModelRef`. The model stays `Pending` until a `MaaSSubscription` and a `MaaSAuthPolicy` include it, even when the pods are healthy:

```
$ oc get maasmodelref -n models-as-a-service
granite-3-3-2b-instruct   Pending
  GovernanceAttached=False  NoPairingFound  "No active subscription and auth policy pairing found"
  RuntimeReady=True         RuntimeHealthy  "Backend is healthy"
```

The platform (rhoai-gitops) only ships the subscription of the demo simulator. The access of the models of this repo is generated here.

## 1. One subscription per tenant namespace

`maas/maas-subscriptions.sh` creates, for every tenant namespace, **one** `MaaSSubscription` (`all-models`) and **one** `MaaSAuthPolicy` (`all-models-policy`) that cover all the `MaaSModelRef`s of the namespace with the same token limit. Rerun it after deploying or deleting a model: it updates the same two resources (`oc apply`), so the new model joins the subscription and a deleted one leaves it.

```bash
maas/maas-subscriptions.sh                       # every AITenant namespace (models-as-a-service, ai-tenant-maas-keycloak, ...)
maas/maas-subscriptions.sh models-as-a-service   # only these namespaces
maas/maas-subscriptions.sh --dry-run             # server-side validation, applies nothing
EXCLUDE=facebook-opt-125m-simulated maas/maas-subscriptions.sh
LIMIT=50000 WINDOW=1m GROUPS_LIST=cluster-admins,team-a maas/maas-subscriptions.sh
```

| Variable | Default | Meaning |
|---|---|---|
| `NAME` | `all-models` | Name of the subscription (the policy is `<name>-policy`) |
| `LIMIT`, `WINDOW` | `100000`, `1h` | Token limit of every model (prompt + completion tokens). The CRD requires one per model |
| `GROUPS_LIST` | `system:authenticated` | Owner groups, comma separated. In a Keycloak tenant they must be the names in the `groups` claim of the token |
| `PRIORITY` | `0` | Picks the default subscription when a user matches several (production 100, staging 50, development 0, sandbox -10) |
| `EXCLUDE` | empty | `MaaSModelRef` names that keep their own subscription, such as the demo simulator (`simulator-free`, `simulator-premium`). A model in two subscriptions makes the API-key subscription choice ambiguous |

Rules the script follows:

- **A subscription never crosses tenants.** Each tenant has its own `maas-api` (it only reads the subscriptions of its namespace, `MAAS_SUBSCRIPTION_NAMESPACE`) and its own gateway-scoped `AuthPolicy`. The CRD would accept a `modelRefs[].namespace` of another tenant, but that is not how a tenant is isolated. A model that must be in both tenants is deployed twice (`serving.maas.tenant`) and each namespace gets its own subscription.
- **Namespaces without `MaaSModelRef` are skipped.**
- **The result is not in git.** The Argo CD applications of rhoai-gitops use `prune: false`, so they leave these resources alone. Run the script against the cluster you are logged into.
- A new model can take a few seconds to become `Ready`; the policy stays `Pending` while the gateway `AuthPolicy` is enforced again (it can take longer if the Kuadrant operator is restarting).

## 2. API key for a model

`maas/maas-api-key.sh [model] [expiration]` creates an API key bound to the highest-priority subscription that includes the model (override with `MAAS_SUBSCRIPTION`) and prints `OPENAI_API_URL` and `OPENAI_API_KEY`:

```bash
eval "$(maas/maas-api-key.sh granite-3-3-2b-instruct 1d)"
curl -s $OPENAI_API_URL/models -H "Authorization: Bearer $OPENAI_API_KEY"
```

You must belong to one of the owner groups of that subscription. The key is shown once; revoke it with `DELETE /maas-api/v1/api-keys/<id>` or from the dashboard. For the Keycloak tenant, request the key with a Keycloak token (see `testing/06-maas/`).
