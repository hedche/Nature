# Scripts

Utility scripts for managing the Nature homelab.

## Contents

| Script | Purpose |
|--------|---------|
| `generate-configs.sh` | In `talos/` — generates Talos configs from templates + secrets |
| `deploy-to-qnap.sh` | In `pxe/` — deploys the QNAP PXE recovery stack |
| `generate-assets.sh` | In `pxe/` — generates iPXE menus from declarative YAML |
| `test-pxe.sh` | In `pxe/` — validates the deployed PXE HTTP/TFTP/Compose service |
| `secrets.sh` | Manage Kubernetes secrets (create, import, push, list, validate) |
| `secrets-crypto.sh` | Encrypt (`-e`) / decrypt (`-d`) secrets.yaml with an age passphrase |
| `validate-cereal-flux.sh` | Validate Flux-managed Kubernetes manifests for the cereal cluster |

## Adding Scripts

- Place new scripts here with descriptive names.
- Add a description row to the table above.
- Ensure scripts check for dependencies before running.
