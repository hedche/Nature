# Public health endpoint

`https://health.cereal.nature.leafbit.uk/healthz` → `ok`

The **only** deliberately public thing this cluster serves. It exists so Grafana Cloud
Synthetics can check the cluster from outside — a genuine outside-in signal that the
cluster, the home internet connection and the cloudflared tunnel are all alive, and one
that shares no dependency with the `remote_write` path.

It is also the first Ingress to use the `cloudflare-tunnel` class. That class and the
`cereal-cluster` tunnel have existed since May but nothing had ever used them; the strrl
controller creates both the tunnel route and the DNS record from this Ingress.

## What it exposes

Nothing. `/healthz` returns the three bytes `ok`; every other path returns 404. No request
echo, no headers reflected, no server tokens, no directory listing — deliberately, because
this is reachable by anyone. Two replicas with soft anti-affinity, so a single node failure
does not make a healthy cluster look dead.

Do **not** add anything else to this namespace, and do not extend this Ingress to proxy
other services. Everything else in this cluster is tailnet-only for a reason.

## Wiring it to Grafana Cloud

In the Grafana Cloud stack → **Testing & synthetics → Checks → Add**:

- Type: HTTP
- Target: `https://health.cereal.nature.leafbit.uk/healthz`
- Frequency: 60s, from 2–3 probe locations
- Expect: status 200

Synthetics does **not** alert by default. Add an alert rule on
`probe_success{job="synthetic"} == 0` for 5m → Telegram + email. See
`../monitoring/README.md` step 7.

## Verify

```sh
export KUBECONFIG=talos/kubeconfig
kubectl -n health get pods -o wide
kubectl -n health get ingress health

curl -sS https://health.cereal.nature.leafbit.uk/healthz   # -> ok
curl -sS -o /dev/null -w '%{http_code}\n' https://health.cereal.nature.leafbit.uk/   # -> 404
```

DNS takes a minute or two to appear after the Ingress is first created. If it never does,
check the controller rather than Cloudflare:

```sh
kubectl -n cloudflared logs deploy/cloudflare-tunnel-ingress-controller | tail -40
```
