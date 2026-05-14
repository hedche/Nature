# Scripts

Utility scripts for managing the Nature homelab.

## Contents

| Script | Purpose |
|--------|---------|
| `generate-configs.sh` | In `talos/` — generates Talos configs from templates + secrets |
| `deploy-to-qnap.sh` | In `pxe/` — deploys the QNAP PXE recovery stack |
| `generate-assets.sh` | In `pxe/` — generates iPXE menus from declarative YAML |
| `test-pxe.sh` | In `pxe/` — validates the deployed PXE HTTP/TFTP/Compose service |

## Adding Scripts

- Place new scripts here with descriptive names.
- Add a description row to the table above.
- Ensure scripts check for dependencies before running.
