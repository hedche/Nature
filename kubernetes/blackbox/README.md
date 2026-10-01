# blackbox-exporter — LAN and WAN reachability

ICMP probes from inside the cluster to the things it depends on but does not run.
Deployed into the `monitoring` namespace (which is already PSA privileged — ICMP needs
`NET_RAW`), but kept in its own Flux Kustomization so it can be removed independently.

| Target | Why |
|---|---|
| `10.30.1.1` | UniFi gateway — if this is unreachable, the switch leg is gone |
| `10.30.1.57` | hermes — NFS server the whole media stack mounts |
| `10.30.1.60` | hassio — the LAN-side watchdog; if it is down, that vantage point is blind |
| `10.30.1.20` | qnap |
| `10.30.1.21` | arctic — WD MyCloud NAS (NFS exports) |
| `1.1.1.1`, `8.8.8.8` | WAN |

The cluster moved indoors on 2026-07-25 and arctic followed on 2026-10-01, so nothing
crosses the garage powerline link any more (it used to be a red-LED Netgear PL1000, under
50 Mbps, that degraded under load). arctic is now a normal GbE LAN host answering in a few
ms; `ArcticLatencyHigh` warns if its RTT climbs past 100ms, which on GbE means the NAS
itself is struggling rather than a slow link.

Alerts live in `rules.yaml`; `probe_success` and `probe_duration_seconds` are in the
remote_write allow-list, so these also reach Grafana Cloud.

## Verify

```sh
export KUBECONFIG=talos/kubeconfig
kubectl -n monitoring get pods -l app.kubernetes.io/name=prometheus-blackbox-exporter
```

Then in the Prometheus UI (`https://prometheus.<tailnet>.ts.net`):

```promql
probe_success{job="blackbox-icmp"}
probe_duration_seconds{job="blackbox-icmp"}
```

All targets should be `1`. If every probe returns 0, the exporter is missing `NET_RAW` —
check that the pod is not being rejected by Pod Security Admission:

```sh
kubectl -n monitoring describe pod -l app.kubernetes.io/name=prometheus-blackbox-exporter
```
