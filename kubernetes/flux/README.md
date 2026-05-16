# Flux CD — GitOps for the cereal cluster

Flux watches this directory (`kubernetes/flux/`) and reconciles manifests to the cluster automatically.

## Setup

1. **Create a GitHub PAT** at <https://github.com/settings/tokens> (fine-grained).
   - Repository access: `hedche/Nature`
   - Permissions: Contents (read/write), Metadata (read)

2. **Store the token** via the secrets pipeline:

   ```bash
   ./scripts/secrets.sh create flux-system \
     -n flux-system \
     --type Opaque \
     --from-literal username=git \
     --from-literal password=YOUR_GITHUB_PAT
   ```

3. **Bootstrap Flux**:

   ```bash
   ./talos/bootstrap.sh bootstrap-flux
   ```

   This runs `flux bootstrap github`, which commits Flux's own manifests into this directory and installs the controllers on the cluster.

## Adding workloads

Place Kustomization and source manifests in this directory (or subdirectories). Flux will pick them up automatically on its next reconciliation interval.

## Useful commands

```bash
flux get all                  # Status of all Flux resources
flux reconcile source git flux-system   # Force a git pull
flux logs --all-namespaces    # Controller logs
```
