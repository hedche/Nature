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

## 5. No manual kubectl changes — avoid cluster drift

All cluster state must be reproducible from this repo. Never apply ad-hoc `kubectl` commands (labels, annotations, RBAC, etc.) that aren't captured in a script or manifest.

- **Node labels**: Worker role labels (`node-role.kubernetes.io/worker`) are applied by `talos/bootstrap.sh` (the `apply-labels` command). Don't label nodes manually.
- **Any new kubectl-managed state** (labels, annotations, taints, RBAC bindings, namespaces, etc.) must be added to `talos/bootstrap.sh` or a Kubernetes manifest in `kubernetes/` so it is reapplied on a full cluster wipe and re-bootstrap.
- **NodeRestriction caveat**: Kubelets cannot self-assign `node-role.kubernetes.io/*` labels (blocked by Kubernetes admission control). These must be applied from an admin kubeconfig, which is why they live in the bootstrap script rather than in `machine.nodeLabels` in Talos configs.

## 6. Kubernetes manifests

- Place in `kubernetes/` directory.
- Use Kustomize or Helm values files for environment-specific config.
- Never embed secrets in plain manifests; use Sealed Secrets or external secret management.
