# Kubernetes Manifests

This directory contains Kubernetes manifests, Helm values, and Kustomize configurations for the Nature homelab.

## Current structure

- `flux/` — Flux bootstrap manifests and Flux Kustomizations.
- `tailscale/` — Tailscale operator and connector resources.
- `headlamp/` — private Kubernetes dashboard exposed through Tailscale Ingress.

## Secret Management

- Never commit plaintext secrets to this repo.
- Kubernetes application secrets are managed via `scripts/secrets.sh` and stored in the same root `secrets.yaml` under the `kubernetes.secrets` key. One file for all secrets.
- The script base64-encodes values when constructing K8s manifests at push time.
