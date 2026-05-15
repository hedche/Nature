# Kubernetes Manifests

This directory will contain Kubernetes manifests, Helm values, and Kustomize configurations for the Nature homelab.

## Planned Structure

```
kubernetes/
├── base/                     # Base manifests (namespaces, RBAC)
├── apps/                     # Application deployments
├── helm/                     # Helm values files
├── secrets/                  # Sealed Secrets or external secret references
└── README.md                 # This file
```

## Secret Management

- Never commit plaintext secrets to this repo.
- Kubernetes application secrets are managed via `scripts/secrets.sh` and stored in the same root `secrets.yaml` under the `kubernetes.secrets` key. One file for all secrets.
- The script base64-encodes values when constructing K8s manifests at push time.
