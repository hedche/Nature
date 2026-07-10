# Kubernetes manifests & GitOps — agent conventions

## Multi-cluster layout

- **cereal** manifests + Flux live here (Flux syncs `./kubernetes/flux`).
- **oracle** manifests + Flux live in `oracle/flux/` (Flux syncs `./oracle/flux`).
- Each cluster runs its own Flux that reconciles **only its own path** — never point
  one cluster's Kustomization at the other's tree. Shared app manifests can be
  referenced from both sync trees.
- Use Kustomize or Helm values files for environment-specific config.
- The `oracle` cluster is K3s (Traefik + local-path built in, no rook-ceph); apps
  needing `ceph-block` storage are cereal-only.

## Secrets pipeline

Kubernetes application secrets are managed via `scripts/secrets.sh` and stored in the
root `secrets.yaml` under the `kubernetes.secrets` key — one file for all secrets.

- **Plaintext storage**: values are plaintext in `secrets.yaml`; the script
  base64-encodes them into K8s Secret manifests at push time.
- **Never embed secrets in plain manifests**, and never `kubectl create secret`
  ad-hoc — always go through the CLI so secrets are reproducible from the repo.
- **Cluster-aware**: an entry may carry `clusters: [name, ...]`; untagged entries are
  shared (pushed everywhere). Push with `scripts/secrets.sh push --cluster cereal`
  or `--cluster oracle`. cereal-only secrets (peanut, tailscale, cloudflare) are
  tagged `clusters: [cereal]`; `flux-system` is shared.
- **Template**: document new secrets in `talos/secrets.yaml.template` under the
  `kubernetes.secrets` example section.
