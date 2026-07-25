# Nature Homelab — Agent Conventions

This repository manages two GitOps Kubernetes clusters — the Talos homelab cluster `cereal` and the Oracle Cloud K3s cluster `oracle` — plus Proxmox VMs, Home Assistant, and QNAP NAS. These global conventions apply everywhere; area-specific rules live in nested `AGENTS.md` files (section 5).

## 1. Secrets — NEVER commit to git

- **Tokens, passwords, private keys, API keys, and certificates must never be committed.**
- A single `secrets.yaml` holds all real values. **It lives outside the repo**, at `~/.config/nature/secrets.yaml`. This repo is public; a file that is not in the working tree cannot be committed by accident, which is a stronger guarantee than `.gitignore` (which `git add -f` overrides and which stops applying entirely once a file is tracked).
- **Never hardcode a secrets path.** Scripts resolve it by sourcing `scripts/secrets-path.sh`, which sets `$SECRETS_FILE`. Never write a path to `secrets.yaml` under `$REPO_ROOT` — that includes temp files.
- Configs that need secrets are kept as **templates with placeholders**; document every new secret's schema in `talos/secrets.yaml.template` with a comment explaining how to generate it.
- Before creating any file that might contain credentials, verify `.gitignore` blocks it — and prefer writing it outside the repo entirely.
- A `gitleaks` pre-commit hook (`.githooks/pre-commit`, rules in `.gitleaks.toml`) blocks staged secrets. **Never bypass it with `SKIP_GITLEAKS=1` or `--no-verify`** — if it fires, either the secret is real (remove it) or the pattern is a placeholder (add a narrow `.gitleaks.toml` allowlist entry, or `# gitleaks:allow` on the line).

## 2. Active vs deprecated infrastructure

- **Active**:
  - **Talos Kubernetes cluster `cereal`** — control plane `cereal` (`10.30.1.50`), workers `snap`/`crackle`/`pop` (`10.30.1.51-.53`)
  - **K3s cluster `oracle`** — Oracle Cloud free-tier ARM, Terraform in `oracle/`
  - **Proxmox VE node `pve`** (`10.30.1.55`) — cloud-init Ubuntu VMs (`10.30.1.56-.59`) via Terraform in `proxmox/`; the `hermes` VM (`10.30.1.57`) runs the media stack deployed from `hermes/`
  - QNAP NAS (`10.30.1.20`), WD MyCloud NAS `arctic` (`10.30.1.21`)
  - Raspberry Pi `photon` — CUPS (`10.30.1.90`); Raspberry Pi `hassio` — Home Assistant (`10.30.1.60`)
- **Deprecated**: anything in `deprecated/` is historical. Do not modify unless explicitly asked.

## 3. IaC philosophy

Every change must be reproducible from this repo + the single secrets file.
- Prefer declarative configs over imperative scripts.
- Document manual steps in READMEs, not inline comments in configs.
- Desired state lives in Git and is pushed to hosts (Terraform, Flux, deploy scripts) — never hand-configure a host and call it done.

## 4. No manual cluster changes — avoid drift

Never apply ad-hoc `kubectl` commands (labels, annotations, RBAC, namespaces, etc.) that aren't captured in a script or manifest. Any new kubectl-managed state must be added to `talos/bootstrap.sh` or a manifest under `kubernetes/` so it survives a full wipe and re-bootstrap. The same spirit applies to hosts: fix the repo and redeploy, don't patch the machine.

## 5. Area-specific conventions (nested AGENTS.md)

The nearest `AGENTS.md` to the files being edited takes precedence. Read the relevant one before working in:

| Directory | Covers |
|-----------|--------|
| `talos/AGENTS.md` | Editing Talos config templates, node labels, bootstrap |
| `kubernetes/AGENTS.md` | Multi-cluster GitOps layout, the `scripts/secrets.sh` pipeline |
| `oracle/AGENTS.md` | OCI Terraform caveats (**do not `terraform apply` casually**) |
| `proxmox/AGENTS.md` | Proxmox VM Terraform, physical disk passthrough |
| `hermes/AGENTS.md` | Media stack (VPN boundary, Tailscale × Docker gotcha) |
