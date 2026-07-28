# Monitoring — kube-prometheus-stack + Grafana Cloud

Hybrid design: Prometheus runs **in** the cluster for fast, WAN-independent alerting and
30 days of local history, and remote_writes a filtered subset **out** to Grafana Cloud so
alerts can also be evaluated somewhere that survives this cluster dying.

That split is the whole point. Every serious incident here — cereal's laptop battery
running flat, the LAN leg going ARP-dead, CoreDNS disappearing with its only node — kills
the cluster, and a Prometheus inside a dead cluster reports nothing.

| Vantage point | Sees | Blind to |
|---|---|---|
| Local Prometheus → Alertmanager → Telegram | everything, within ~30s | itself, and anything that kills the cluster |
| Grafana Cloud rules on remote_written metrics | the cluster going silent | your home internet being the thing that broke |
| Home Assistant on the LAN (`../../home-assistant/`) | the whole LAN, including this stack, going dark | anything above the LAN |

| URL | Purpose |
|---|---|
| `https://prometheus.<tailnet>.ts.net` | Prometheus UI — targets, rules, ad-hoc PromQL |
| `https://alertmanager.<tailnet>.ts.net` | Alertmanager UI — silences, current alerts |
| Grafana Cloud stack | dashboards, off-site alerting, logs |

Neither local UI has authentication. The tailnet ACL is the security boundary, exactly as
for headlamp. **Never** expose them through cloudflared.

## What is here

| Path | Purpose |
|---|---|
| `helmrelease.yaml` | the whole stack: Prometheus, Alertmanager, node-exporter, kube-state-metrics, operator. Local Grafana disabled — Grafana Cloud is the UI |
| `rules/` | homelab-specific `PrometheusRule`s, plus the recording rules that feed remote_write |
| `node-problem-detector/` | DaemonSet reading `/dev/kmsg` for NVMe DMA faults and kubelet healthz — see below |
| `servicemonitor-ceph.yaml` | scrapes rook's existing mgr and exporter Services |
| `ingress-*.yaml` | tailscale Ingresses for the two debug UIs |

## The cardinality budget

Grafana Cloud's free tier caps metrics at **10,000 active series and silently drops the
excess**. A partially-dropped dead-man's switch looks exactly like a working one, so the
allow-list is deliberately conservative.

Raw local cardinality is ~50–70k series (apiserver histograms ~15k and kube-state-metrics
~12k dominate). Two mechanisms cut what leaves the cluster to **~2,000 series**:

1. `rules/remote-write-recording.yaml` collapses per-pod and per-container dimensions
   locally. cAdvisor alone goes from ~7,000 series to ~10.
2. `remoteWrite.writeRelabelConfigs` in `helmrelease.yaml` keeps an explicit metric-name
   allow-list and drops the labels (`uid`, `pod_ip`, `container_id`, …) that mint a fresh
   series on every pod restart.

To see what is actually being shipped:

```sh
# Locally — the biggest offenders by name
topk(20, count by (__name__) ({__name__!=""}))

# In Grafana Cloud — ground truth
grafanacloud_instance_active_series
```

**Do not click "Install Kubernetes Monitoring" in the Grafana Cloud UI.** That activates a
separately-billed SKU charged on host-hours (2,232/mo free = 3 nodes 24/7) and
container-hours (37,944/mo free = 51 containers 24/7). This cluster is 4 nodes and ~122
containers, so it would run out around day 13 of every month.

## NVMe DMA-fault detection

`node-problem-detector/` exists for one specific failure: crackle went NotReady on
2026-07-18 and stayed down until a physical power-cycle on 2026-07-27, and **nothing
watching from outside the node noticed** — ICMP, Talos apid, `talosctl services` and Ceph
all reported healthy. Full write-up in `docs/nvme-dma-fault-monitoring.md`.

NPD reads `/dev/kmsg`, which on Talos carries both kernel messages and Talos service logs,
so one reader catches the `DMAR:.*fault` storm *and* the `failed to lock device` loop that
follows. A custom plugin additionally polls kubelet healthz on `127.0.0.1:10248` — it binds
loopback only, hence `hostNetwork: true` on the DaemonSet.

Problems surface three ways: as Node Conditions, as `problem_counter`/`problem_gauge`
metrics (alerted on in `rules/nature-hardware.yaml`), and — because Node Conditions flow
through kube-state-metrics as `kube_node_status_condition`, which is in the allow-list —
in Grafana Cloud too.

**Test it synthetically.** The current boot is clean, so there is nothing real to observe:

```sh
kubectl -n monitoring debug node/crackle -it --image=busybox --profile=sysadmin -- \
  sh -c 'for i in $(seq 1 15); do echo "DMAR: [DMA Read NO_PASID] Request device [01:00.0] fault addr 0x0 [fault reason 0x06] PTE Read access is not set" > /dev/kmsg; done'

kubectl get node crackle -o jsonpath='{range .status.conditions[*]}{.type}={.status}{"\n"}{end}'
```

Expect `NVMeDMAFault=True` and a Telegram message. Clearing it needs an NPD restart
(permanent conditions do not self-reset):
`kubectl -n monitoring rollout restart daemonset/node-problem-detector`.

## Secrets

All pushed by `scripts/secrets.sh push --cluster cereal`; schemas documented in
`talos/secrets.yaml.template`.

| Secret | Namespace | Keys |
|---|---|---|
| `grafana-cloud-credentials` | `monitoring` | `prometheus-username`, `prometheus-token` |
| `alertmanager-telegram` | `monitoring` | `bot-token` |
| `nature-vars` | `flux-system` | `TELEGRAM_CHAT_ID`, `GRAFANA_CLOUD_PROM_URL`, `GRAFANA_CLOUD_LOKI_URL`, `GRAFANA_CLOUD_LOKI_USERNAME` |

`nature-vars` is consumed by Flux `postBuild.substituteFrom`, not mounted. The chat ID and
endpoint URLs are identifiers rather than credentials, but Nature is a public repo so they
are kept out of the tree all the same.

Two things to know about how Flux substitution fails, both verified against v2.6.4:

- A **missing Secret** fails the whole Kustomization loudly — nothing is applied. So
  `nature-vars` must exist *before* this is pushed.
- A **missing key** inside an existing Secret silently substitutes an empty string. That
  is survivable here only because both consumers reject it at startup (an empty
  `remoteWrite.url` stops Prometheus loading its config; an empty `chat_id` stops
  Alertmanager). Do not add a `${VAR}` whose empty value would be *accepted*. The
  `${VAR:?message}` guard does **not** work — Flux substitutes the message text as the
  value, which is worse than nothing.

Only the braced `${VAR}` form is substituted, so Prometheus's `$labels` and `$value`
templating in `rules/` passes through untouched.

## Grafana Cloud setup — manual, in this order

Nothing below can be GitOps'd today. See the Terraform note at the end.

1. Create a free Grafana Cloud stack, EU region. **Skip the "Install Kubernetes
   Monitoring" onboarding flow** (see the cardinality section above).
2. Stack → **Details**: note the Prometheus remote_write URL and its numeric instance ID,
   and the Loki push URL (`.../loki/api/v1/push`) and its user ID.
3. **Administration → Cloud access policies** → create `cereal-write`, scopes
   `metrics:write` and `logs:write` only. Create a token; copy it once.
4. Store everything locally, never in git:
   ```sh
   ./scripts/secrets.sh create grafana-cloud-credentials -n monitoring \
     --from-literal prometheus-username=<instance-id> \
     --from-literal prometheus-token=<token>

   ./scripts/secrets.sh create alertmanager-telegram -n monitoring \
     --from-literal bot-token=<the TELEGRAM_BOT_TOKEN already stored for peanut>

   ./scripts/secrets.sh create flux-telegram-token -n flux-system \
     --from-literal token=<same bot token>

   ./scripts/secrets.sh create nature-vars -n flux-system \
     --from-literal TELEGRAM_CHAT_ID=<chat id> \
     --from-literal GRAFANA_CLOUD_PROM_URL=<remote_write url> \
     --from-literal GRAFANA_CLOUD_LOKI_URL=<loki push url> \
     --from-literal GRAFANA_CLOUD_LOKI_USERNAME=<loki user id>

   ./scripts/secrets.sh create grafana-cloud-credentials -n logging \
     --from-literal loki-token=<token>
   ```
   Add `clusters: [cereal]` to each new entry in `~/.config/nature/secrets.yaml`, then:
   ```sh
   ./scripts/secrets.sh push --cluster cereal
   ./scripts/secrets-crypto.sh -e
   ```
   Note the duplicate `grafana-cloud-credentials` in `logging` — Secrets are not
   cross-namespace.
5. **Alerting → Contact points**: `telegram-lydia` and `email-lydia`
   (lydia@leafbit.uk). Send a test to each. Notification policy: default → Telegram,
   nested `severity=critical` → both.
6. **Alerting → Alert rules** — the off-site half of the design. For every one of these,
   set **"Alert state if no data" to `Alerting`** (the default, `NoData`, does not notify)
   and the evaluation interval to 1m:

   | Rule | Query | For |
   |---|---|---|
   | `ClusterSilent` (the dead-man's switch) | `absent(nature:cluster_heartbeat{cluster="cereal"})` | 5m |
   | `NoDataFromCereal` | `absent(up{job="node-exporter",cluster="cereal"})` | 5m |
   | `NodeMissing` | `count(up{job="node-exporter",cluster="cereal"} == 1) < 4` | 10m |
   | `CerealOnBatteryCloud` | `node_power_supply_online{power_supply="ACAD"} == 0` | 5m |
   | `NVMeDMAFaultCloud` | `kube_node_status_condition{condition="NVMeDMAFault",status="true"} == 1` | 5m |
   | `CephUnhealthyCloud` | `ceph_health_status > 0` | 30m |
   | `PublicEndpointDown` | `probe_success{job="synthetic"} == 0` | 5m |
   | `SeriesCapApproaching` | `grafanacloud_instance_active_series > 8000` | 1h |

   `CerealOnBatteryCloud` duplicates a local rule on purpose — it survives the local
   Alertmanager failing.
7. **Testing & synthetics → Checks**: HTTP check against the public `/healthz`
   (`../health/`), 60s, 2–3 locations. Synthetics does not alert on its own; wire
   `probe_success` into the rule above.
8. After 24h: **Administration → Cost management** → confirm active series below 3,000 and
   logs below 500 MB/day.

**Terraform?** `proxmox/` and `oracle/` already use it, and the `grafana/grafana` provider
covers contact points, rule groups and synthetic checks — so porting this is worth doing
*eventually*. Not yet: writing rule groups blind against an unfamiliar API adds a state
file and an API token for no immediate benefit. Live with the clicked version for a month,
then export the working rule groups as provisioning YAML from the Grafana UI, which makes
the port nearly mechanical.

## Operations

```sh
export KUBECONFIG=talos/kubeconfig

kubectl -n monitoring get pods -o wide          # Prometheus must NOT be on cereal
kubectl -n monitoring logs sts/prometheus-kube-prometheus-stack-prometheus -c prometheus

# Is anything failing to reach Grafana Cloud?
kubectl -n monitoring exec -it sts/prometheus-kube-prometheus-stack-prometheus -c prometheus \
  -- wget -qO- localhost:9090/api/v1/query?query=prometheus_remote_storage_samples_failed_total

# Silence an alert while working on it
#   https://alertmanager.<tailnet>.ts.net → Silences → New
```

**Never silence `Watchdog`.** It is the always-firing alert whose absence Home Assistant
uses as the LAN-side dead-man's switch.

## Known gaps

- `kubeControllerManager`, `kubeScheduler` and `kubeEtcd` scraping are **disabled** in
  `helmrelease.yaml`. The first two bind `127.0.0.1` on Talos until the `bind-address`
  change in `talos/controlplane.yaml` is applied; flip them to `true` afterwards. etcd
  needs a machine-config change of its own and is deferred — on a single-control-plane
  cluster the etcd static-pod restart is the riskiest change available.
- No metrics-server, so no `kubectl top` and no HPAs. That needs
  `machine.kubelet.extraArgs.rotate-server-certificates` plus the kubelet-serving-cert
  approver, which must be deployed *before* the flag is flipped or kubelet CSRs sit
  pending. Worth doing as an isolated change, cereal last.
