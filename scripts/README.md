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
| `secrets-path.sh` | **Sourced, not run** — resolves `$SECRETS_FILE`. The one place the secrets location is defined |
| `validate-cereal-flux.sh` | Validate Flux-managed Kubernetes manifests for the cereal cluster |

## Adding Scripts

- Place new scripts here with descriptive names.
- Add a description row to the table above.
- Ensure scripts check for dependencies before running.
- **Need secrets?** `source "${REPO_ROOT}/scripts/secrets-path.sh"` and use
  `$SECRETS_FILE`. Never hardcode a path — `secrets.yaml` lives outside the repo
  (`~/.config/nature/`) precisely so it cannot be committed to this public repo.

## Pre-commit Secret Scanning

`.githooks/pre-commit` runs `gitleaks` against the staged diff (~30ms) and
blocks the commit if it finds a secret. Git hooks are not cloned, so enable it
once per clone:

```bash
brew install gitleaks
git config core.hooksPath .githooks
```

Rules live in `.gitleaks.toml`. On a false positive, add a narrow allowlist
entry there or append `# gitleaks:allow` to the line — `SKIP_GITLEAKS=1 git
commit` exists as a last resort, but a bypass that becomes habit defeats the
hook. Scan full history at any time with:

```bash
gitleaks git --log-opts="--all" --redact
```
