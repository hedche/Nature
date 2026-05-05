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
- Use Sealed Secrets, External Secrets Operator, or SOPS for Kubernetes secrets.
- The root `secrets.yaml` (gitignored) holds Talos-level secrets only.
