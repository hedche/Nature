# Kubernetes Manifests

This directory contains Kubernetes manifests, Helm values, and Kustomize configurations for the Nature homelab.

## Current structure

- `flux/` — Flux bootstrap manifests and Flux Kustomizations.
- `tailscale/` — Tailscale operator and connector resources.
- `headlamp/` — private Kubernetes dashboard exposed through Tailscale Ingress.
- `peanut/` — Trello daily-briefing assistant (web app + CronJob).
- `media/` — Sonarr/Radarr/Prowlarr, pointed at qBittorrent + NFS storage on the hermes VM (see `media/README.md`).
- `monitoring/` — kube-prometheus-stack + node-problem-detector, remote_writing a filtered subset to Grafana Cloud (see `monitoring/README.md`).
- `logging/` — Grafana Alloy shipping filtered pod logs to Grafana Cloud Loki.
- `blackbox/` — ICMP probes for the LAN, the WAN, and the garage powerline link.
- `notifications/` — Flux `Provider`/`Alert` routing reconciliation failures to Telegram.
- `health/` — the one deliberately public endpoint, for Grafana Cloud Synthetics.

Monitoring is a hybrid: Prometheus runs here for fast local alerting, and Grafana Cloud
evaluates the same signals off-site so that alerts still fire when the cluster itself dies.
The third vantage point is Home Assistant on the LAN — see `../home-assistant/README.md`.

## Secret Management

- Never commit plaintext secrets to this repo.
- Kubernetes application secrets are managed via `scripts/secrets.sh` and stored in the same `secrets.yaml` under the `kubernetes.secrets` key. One file for all secrets.
- The script base64-encodes values when constructing K8s manifests at push time.
