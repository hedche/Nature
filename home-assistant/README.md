# Home Assistant

Home Assistant OS on a dedicated Raspberry Pi 4B (`hassio`, 10.30.1.60), managed
independently of the Talos cluster.

Its role in this repo is narrow but important: **it is the third vantage point for cluster
monitoring.** Separate hardware, on the same LAN, with phone push already working — so it
is the one observer that survives the entire cereal cluster going away.

| Vantage point | Answers |
|---|---|
| Local Prometheus (`kubernetes/monitoring/`) | "the cluster can't reach Grafana Cloud" |
| Grafana Cloud alert rules | "the cloud can't hear the cluster" |
| **Home Assistant (here)** | "the whole LAN, including the monitoring stack, is dark" |

No shared dependency between the three, which is the point.

## `packages/nature-watchdog.yaml`

| Signal | Detects |
|---|---|
| ping `.50`–`.53` | individual nodes going away |
| all four `off` at once | the LAN/switch leg outage that recurred on 2026-07-15, -24 and -25 |
| TCP `10.30.1.50:6443` | the API server hung while the node still pings — the shape of the 2026-07-18 crackle outage |
| heartbeat webhook | Alertmanager's always-firing `Watchdog` alert, POSTed every minute. **Its absence for 15 minutes is the dead-man's switch.** |

The heartbeat is fed by the `home-assistant-heartbeat` receiver in
`kubernetes/monitoring/helmrelease.yaml`. Never silence the `Watchdog` alert in
Alertmanager — doing so disables this.

## Deploying it — manual, and that is a real gap

Home Assistant OS `/config` is reachable by neither Flux nor Ansible today, so this file is
**version-controlled here but copied by hand**. It will drift. That is a known cost, not an
oversight.

1. Ensure `/config/configuration.yaml` on hassio contains:
   ```yaml
   homeassistant:
     packages: !include_dir_named packages
   ```
2. Copy the file to `/config/packages/nature-watchdog.yaml` — via the File Editor or
   Samba add-on, or over SSH as `root@hassio`.
3. Replace every `notify.mobile_app_REPLACE_ME` with your actual companion-app entity
   (Developer Tools → Actions → search "notify").
4. Developer Tools → **Check configuration**, then **Restart**.

### Verify

```yaml
# Developer Tools -> Template
{{ states('binary_sensor.cereal_node_up') }}
{{ states('binary_sensor.nature_cluster_lan_leg_up') }}
{{ states('input_datetime.nature_last_heartbeat') }}
```

Then prove the dead-man's switch actually fires, rather than assuming it does:

```sh
export KUBECONFIG=talos/kubeconfig
kubectl -n monitoring scale sts/alertmanager-kube-prometheus-stack-alertmanager --replicas=0
# wait ~16 minutes -> expect a critical phone push
kubectl -n monitoring scale sts/alertmanager-kube-prometheus-stack-alertmanager --replicas=1
```

## Closing the manual-copy gap

The repo already has `ansible/` for the `photon` Pi. An `ansible/roles/home-assistant` role
that rsyncs `home-assistant/packages/` to `/config/packages/` over the SSH add-on and then
calls a restart would make this properly declarative, and it fits the repo's stated
"desired state lives in Git and is pushed to hosts" philosophy. Worth doing once the
watchdog config has settled.

## Notes

- The `ping` **binary_sensor YAML platform has been removed** from Home Assistant — it is
  config-flow/UI only now. Hence `command_line` throughout.
- HA secrets (tokens, the Octopus/energy integration, ZHA pairings) are **not** in this
  repo and should not be. Only declarative automation config belongs here.
