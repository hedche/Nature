# Flux notifications

Routes Flux reconciliation **failures** to Telegram via notification-controller (which
has been installed as part of `gotk-components.yaml` since bootstrap, but had no
`Provider`/`Alert` objects until now).

| Object | Purpose |
|---|---|
| `Provider/telegram` | Telegram bot endpoint + chat |
| `Alert/flux-failures` | `eventSeverity: error` from every source kind |
| `Alert/flux-info` | deploy-success chatter — **suspended** by default |

This complements, rather than duplicates, the `FluxReconciliationFailing` PrometheusRule
in `../monitoring/rules/nature-cluster.yaml`: the Provider gives you the *event text*
immediately, the rule tells you it has been *broken for 15 minutes*. The `exclusionList`
keeps the two from double-notifying on transient reconcile ordering.

## Secrets

Two entries, both pushed by `scripts/secrets.sh push --cluster cereal`:

| Secret | Namespace | Keys | Notes |
|---|---|---|---|
| `flux-telegram-token` | `flux-system` | `token` | Reuse the `TELEGRAM_BOT_TOKEN` already stored for peanut |
| `nature-vars` | `flux-system` | `TELEGRAM_CHAT_ID` | Consumed by `postBuild.substituteFrom`, not mounted |

The chat ID is *not* inlined in the manifest. `Provider` has no `secretRef` key for the
channel, and Nature is a public repo, so it is injected at apply time via the Flux
Kustomization's `postBuild.substituteFrom` (see `../flux/notifications.yaml`).

## Verify

```sh
flux get alerts
flux -n flux-system reconcile kustomization notifications

# Force a failure and expect a Telegram message within ~1m:
flux suspend kustomization media && flux resume kustomization media
```

If nothing arrives, check the controller rather than the bot:

```sh
kubectl -n flux-system logs deploy/notification-controller | tail -50
```

A `400 Bad Request` from `api.telegram.org` almost always means the substitution did not
happen — confirm the `nature-vars` Secret exists and that the rendered Provider has
a numeric `channel`:

```sh
kubectl -n flux-system get provider telegram -o jsonpath='{.spec.channel}'
```
