# Logging — Grafana Alloy → Grafana Cloud Loki

A Grafana Alloy DaemonSet shipping filtered pod logs off-site. Logs are queried in the
Grafana Cloud stack (Explore → Loki), alongside the metrics from `../monitoring/`.

**Logs only.** This is deliberately *not* the `k8s-monitoring` Helm chart: that one
activates Grafana Cloud's separately-billed Kubernetes Monitoring SKU, whose free
allowance (3 nodes, 51 containers) this cluster is roughly 2.5× too large for.

## Why the API reader, not hostPath

Alloy uses `loki.source.kubernetes`, which reads pod logs through the Kubernetes API,
rather than `loki.source.file` over a hostPath `/var/log/pods` mount. The cluster-wide PSA
default is `enforce: baseline`, which blocks hostPath — so this keeps the `logging`
namespace at `baseline` instead of needing a second privileged namespace. The cost is a
little extra apiserver load. If that ever shows up in the apiserver latency panels, switch
to the file source and add `pod-security.kubernetes.io/enforce: privileged` to
`namespace.yaml`.

## The volume budget

Grafana Cloud's free tier allows **50 GB/month**, i.e. 1.67 GB/day. Expected here is
~150–400 MB/day, achieved by dropping, in order of how much they cost:

| Dropped | Why |
|---|---|
| every namespace not on the allow-list | most namespaces are never debugged from logs |
| `cilium` pods | cilium-agent at INFO is roughly half of total volume |
| `csi-*` sidecars, `log-collector` | rook already writes rotated logs to the host |
| health-check request lines | the largest single category of useless lines |
| DEBUG/TRACE in `kube-system`, `rook-ceph`, `tailscale` | keep WARN and above for infra; keep everything for app namespaces |

Check actual usage after 48h:

```logql
sum(bytes_over_time({cluster="cereal"}[24h]))
```

and in Grafana Cloud → **Administration → Cost management → Logs**. If it runs hot, drop
`media` first (Sonarr and Radarr are verbose) or add a `stage.sampling`.

## Secrets

| Secret | Namespace | Keys |
|---|---|---|
| `grafana-cloud-credentials` | `logging` | `loki-token` |
| `nature-vars` | `flux-system` | `GRAFANA_CLOUD_LOKI_URL`, `GRAFANA_CLOUD_LOKI_USERNAME` |

Note the `grafana-cloud-credentials` name is reused in the `monitoring` namespace with
different keys — Secrets are not cross-namespace, so there are two entries in
`~/.config/nature/secrets.yaml`. Setup runbook is in `../monitoring/README.md`.

## Verify

```sh
export KUBECONFIG=talos/kubeconfig
kubectl -n logging get pods -o wide          # one per node, cereal included
kubectl -n logging logs ds/alloy | tail -30  # look for loki.write errors
```

Then in Grafana Cloud → Explore → Loki:

```logql
{cluster="cereal", namespace="flux-system"}
```

A 401 from `loki.write` means the token lacks `logs:write`; a 429 means you are over the
ingest rate and the drops above need tightening.
