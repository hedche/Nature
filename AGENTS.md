# Nature Homelab — Agent Conventions

This repository manages a Talos Kubernetes homelab plus Home Assistant and QNAP NAS. These conventions must be followed by all agents working on this codebase.

## 1. Secrets — NEVER commit to git

- **Tokens, passwords, private keys, API keys, and certificates must never be committed.**
- Talos configs that contain secrets are kept as **templates with placeholders** (`${VAR_NAME}`).
- A single `secrets.yaml` file (at repo root, gitignored) holds all real values. The user backs this up encrypted externally.
- The `talos/generate-configs.sh` script produces runnable configs from templates + secrets.yaml.
- Before creating any file that might contain credentials, verify `.gitignore` blocks it.

## 2. Active vs deprecated infrastructure

- **Active**: Talos Kubernetes (1 control plane, 3 workers), QNAP NAS, Raspberry Pi (Home Assistant).
- **Deprecated**: Anything in `deprecated/` is historical. Do not modify unless explicitly asked.
- Old Ubuntu server configs (`blackhole/`, `cloudmon/`, `habitat/`, `proxmox`, `uni-setup.sh`, `git.sh`) have been moved to `deprecated/`.

## 3. IaC philosophy

Every change must be reproducible from this repo + the single secrets file.
- Prefer declarative configs over imperative scripts.
- Document manual steps in READMEs, not inline comments in configs.
- If a value is sensitive, use a template placeholder and document it in `secrets.yaml.template`.

## 4. When changing Talos configs

- Edit the `.template` versions, not generated configs.
- Add any new placeholder to `secrets.yaml.template` with a comment explaining how to generate it.
- Run `bash -n talos/generate-configs.sh` to check script syntax after changes.

## 5. Kubernetes manifests

- Place in `kubernetes/` directory.
- Use Kustomize or Helm values files for environment-specific config.
- Never embed secrets in plain manifests; use Sealed Secrets or external secret management.
