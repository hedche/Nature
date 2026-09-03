# Grafana Cloud — Terraform

The off-site half of the monitoring design (`../kubernetes/monitoring/`). Everything
here is declarative except the two steps Grafana genuinely cannot automate.

## What you must do by hand (there are exactly two)

Researched rather than assumed: there is **no** REST endpoint, CLI or MCP server that
can create a Grafana Cloud account, and `grafana_cloud_stack` cannot create a stack on
the free tier — it works only on paid accounts. Everything after these two steps is
Terraform.

**1. Create the account and a free stack.** <https://grafana.com/auth/sign-up/create-user>,
EU region. **Do not run the "Install Kubernetes Monitoring" onboarding** — that activates a
separately-billed SKU charged on host- and container-hours, and this cluster (4 nodes,
~122 containers) would exhaust the free allowance around day 13 of every month.

**2. Mint one bootstrap token.** grafana.com → Administration → Cloud access policies →
Create access policy:

| Field | Value |
|---|---|
| Realm | `org` |
| Scopes | `accesspolicies:read`, `accesspolicies:write`, `accesspolicies:delete`, `stacks:read`, `stack-service-accounts:write` |

Then **Add token** on that policy. Put it and the stack slug in
`~/.config/nature/secrets.yaml`:

```yaml
grafana:
  cloud_access_policy_token: "glc_..."
  stack_slug: "<your-stack>"        # the <slug> in <slug>.grafana.net
```

That token is the only credential you create by hand. Terraform mints the stack service
account, the push token and the Synthetics publisher token itself.

## Apply

```sh
cd grafana
direnv allow                 # exports TF_VAR_* from secrets.yaml
terraform init

# Two-phase on a cold state: provider grafana.sm reads a token from a resource
# created in the same run, so the installation must exist before the rest plans.
terraform apply -target=grafana_synthetic_monitoring_installation.this
terraform apply
```

## Copy the outputs back into the cluster

```sh
./scripts/secrets.sh create grafana-cloud-credentials -n monitoring \
  --from-literal prometheus-username="$(terraform -chdir=grafana output -raw prometheus_username)" \
  --from-literal prometheus-token="$(terraform -chdir=grafana output -raw push_token)"

./scripts/secrets.sh create grafana-cloud-credentials -n logging \
  --from-literal loki-token="$(terraform -chdir=grafana output -raw push_token)"
```

Then add these to the existing `nature-vars` entry (it already holds `TELEGRAM_CHAT_ID`
and `TELEGRAM_CHAT_ID_STR`) and push:

| Key | From |
|---|---|
| `GRAFANA_CLOUD_PROM_URL` | `terraform output -raw prometheus_url` |
| `GRAFANA_CLOUD_LOKI_URL` | `terraform output -raw loki_url` |
| `GRAFANA_CLOUD_LOKI_USERNAME` | `terraform output -raw loki_username` |

```sh
./scripts/secrets.sh push --cluster cereal
./scripts/secrets-crypto.sh -e
```

Finally uncomment the `remoteWrite` block in
`../kubernetes/monitoring/helmrelease.yaml` and the `logging.yaml` line in
`../kubernetes/flux/kustomization.yaml`, and push.

## The trap this config exists to avoid

Grafana-managed rules are **not** Prometheus rules, and the difference silently inverts
the natural phrasing.

In Prometheus a comparison *filters*: `x == 0` returns an empty vector when false, and
empty means "not firing". Grafana instead classifies an empty result as **No Data** and
applies `no_data_state`. So `absent(...)`, `x == 0`, `x > 0`, `< 4` all return empty
during **normal** operation — and under a blanket `no_data_state = Alerting` every one of
them fires permanently, carrying zero information. Worse, a rule stuck firing never
resolves, so a real outage produces no new notification at all.

Grafana's own guidance: *"Grafana Alerting implements a built-in No Data state logic, so
you don't need to detect missing data with `absent_*` queries."*

Every rule in `rules.tf` therefore has the same shape:

- **A** — PromQL returning a bare number, no comparison, forced to always produce a sample
  with `or on() vector(0)` where the series can vanish entirely
- **B** — a threshold expression holding the comparison; this is the rule condition

and `no_data_state` is a per-rule judgement about whether missing data is itself the bad
news, never a blanket setting. `SeriesCapApproaching` and `LocalAlertUndelivered` use
`OK`, because for those two an empty result is the healthy case.

An expression stage cannot rescue a filtering query: Grafana's expression engine
propagates No Data, so Reduce/Threshold over an empty frame is still No Data. The fix has
to live in the PromQL.

The local `PrometheusRule`s in `../kubernetes/monitoring-rules/rules/` are the opposite
case — Prometheus has no No Data concept, so the `absent()` calls there are correct and
must be left alone.

## Costs

Synthetics is metered on the free tier: **100k API-test executions/month**, per probe,
rounded up to the minute. The formula is `probes × 43,200 / frequency_minutes`:

| Config | Executions/month | |
|---|---|---|
| 2 probes @ 60s | 86,400 | fits, but 86% of the allowance |
| 3 probes @ 60s | 129,600 | **over** |
| 3 probes @ 120s | 64,800 | what `synthetics.tf` uses |

## Gotchas worth knowing before editing

- `access_policy_id` must be `.policy_id`, not `.id` — `.id` is the composite
  `{region}:{policyId}` and the Cloud API returns 404 rather than a Terraform error.
- `realm.identifier` is the **numeric** stack id for `type = "stack"`.
- `region` must be the full region slug (`prod-eu-west-0`), never `"eu"`.
- Never compute `expires_at` from `timestamp()` — it is ForceNew, so it silently rotates
  the credential on every apply.
- Telegram chat ids are negative and must stay **quoted strings**.
- Synthetics `frequency`/`timeout` are **milliseconds**.
- The Synthetics `job` label must stay `"synthetic"` or `PublicEndpointDown` never matches.
- `grafana_notification_policy` owns the **entire** tree — UI edits are replaced on apply.
- `terraform.tfstate` holds the push token in plaintext and is gitignored. Do not commit it.
