# Nature Homelab — Agent Conventions

This repository manages two GitOps Kubernetes clusters — the Talos homelab cluster `cereal` and the Oracle Cloud K3s cluster `oracle` — plus Home Assistant and QNAP NAS. These conventions must be followed by all agents working on this codebase.

## 1. Secrets — NEVER commit to git

- **Tokens, passwords, private keys, API keys, and certificates must never be committed.**
- Talos configs that contain secrets are kept as **templates with placeholders** (`${VAR_NAME}`).
- A single `secrets.yaml` file (at repo root, gitignored) holds all real values. The user backs this up encrypted externally.
- The `talos/generate-configs.sh` script produces runnable configs from templates + secrets.yaml.
- Before creating any file that might contain credentials, verify `.gitignore` blocks it.

## 2. Active vs deprecated infrastructure

- **Active**:
  - **Talos Kubernetes cluster `cereal`** (1 control plane, 3 workers)
    - `cereal` — control plane (`10.30.1.50`)
    - `snap` — worker (`10.30.1.51`)
    - `crackle` — worker (`10.30.1.52`)
    - `pop` — worker (`10.30.1.53`)
  - **K3s cluster `oracle`** — Oracle Cloud free-tier ARM, provisioned by Terraform in `oracle/`. Public cluster; control plane + 1 worker. Adopted from `~/dv/oci-k8s-terraform` (state copied in; do not run Terraform from the old repo).
  - **Proxmox VE node `pve`** (`10.30.1.55`) — hosts standalone cloud-init Ubuntu VMs (IPs `10.30.1.56-.59`) defined by Terraform in `proxmox/`. The `hermes` VM (`10.30.1.57`) also runs the VPN torrent stack (Gluetun + qBittorrent) deployed from `hermes/`.
  - QNAP NAS (`10.30.1.20`)
  - Raspberry Pi `photon` — CUPS server (`10.30.1.90`)
  - Raspberry Pi `hassio` — Home Assistant (`10.30.1.60`)
  - WD MyCloud NAS `arctic` (`10.30.1.21`)
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

## 6. Kubernetes manifests & multi-cluster GitOps

- **cereal** manifests + Flux live in `kubernetes/` (Flux syncs `./kubernetes/flux`).
- **oracle** manifests + Flux live in `oracle/flux/` (Flux syncs `./oracle/flux`). The `oracle/` dir also holds that cluster's Terraform infra and its `.envrc`/`bootstrap.sh`.
- Each cluster runs its own Flux that reconciles **only its own path** — never point one cluster's Kustomization at the other's tree. Shared app manifests can be referenced from both sync trees.
- Use Kustomize or Helm values files for environment-specific config.
- Never embed secrets in plain manifests; use the Kubernetes secrets pipeline (section 7).
- The `oracle` cluster is K3s (Traefik + local-path storage built in); it has **no** rook-ceph. Apps needing `ceph-block` storage are cereal-only.

## 6a. Oracle Terraform — important caveats

- **`oracle/` is the source of truth** for the OCI cluster. It was adopted from
  `~/dv/oci-k8s-terraform` by copying the Terraform state in (gitignored). **Do not
  run Terraform from the old repo** — both pointing at the same infra causes
  split-brain. Treat the old repo as archived.
- **Do not `terraform apply` in `oracle/`** unless you intend to rebuild the cluster.
  `terraform plan` shows both instances "must be replaced" because the live nodes'
  cloud-init `user_data` predates edits to `cloud-init/*.tpl` (pre-existing drift,
  identical in the source repo). Applying destroys and recreates both nodes — new
  instances, new public IPs, new kubeconfig. Running Flux/GitOps does **not** require
  apply; the cluster is already up.
- State, `terraform.tfvars`, and `kubeconfig.yaml` are gitignored — never commit them.

## 6b. Proxmox Terraform

- **`proxmox/` is the source of truth** for what runs on the Proxmox node `pve`
  (`10.30.1.55`): standalone cloud-init Ubuntu 24.04 VMs, provisioned via the
  `bpg/proxmox` provider. Local Terraform state, no remote backend (mirrors `oracle/`).
- VMs are declared in the `vms` map in `terraform.tfvars` — add/remove an entry and
  `terraform apply`. Per-VM fields override `vm_defaults`. Keep specs modest (node is
  4 threads / 15 GB / ~56 GB `local-lvm`); use IPs `10.30.1.56-.59` (the node is `.55`,
  the k8s nodes are `.50-.53`) on the shared `/24`.
- Auth is a dedicated API token (`terraform@pve`), stored in the root `secrets.yaml`
  under the `proxmox:` key and loaded into Terraform via `proxmox/.envrc`
  (`TF_VAR_proxmox_api_token`). The token is never committed; `proxmox/README.md`
  documents the one-time `pveum` token-creation steps.
- State and `terraform.tfvars` are gitignored — never commit them.

## 7. Kubernetes secrets pipeline

Kubernetes application secrets are managed via `scripts/secrets.sh` and stored in the **same root `secrets.yaml`** under the `kubernetes.secrets` key — one file for all secrets.

- **Single file**: Talos secrets (`talos:`), CUPS secrets (`cups:`), and Kubernetes secrets (`kubernetes.secrets:`) all live in root `secrets.yaml`. No separate secrets files.
- **Plaintext storage**: Values are stored as plaintext in `secrets.yaml`; the script base64-encodes them when constructing K8s manifests at push time.
- **CLI tool**: Use `scripts/secrets.sh` to create, import, push, list, show, delete, and validate secrets.
- **Cluster-aware**: An entry may carry an optional `clusters: [name, ...]` list. Entries with no `clusters` field are shared (pushed to every cluster); tagged entries only go to the named clusters. Push with `scripts/secrets.sh push --cluster cereal` or `--cluster oracle`. cereal-only secrets (peanut, tailscale, cloudflare) are tagged `clusters: [cereal]`; `flux-system` is shared.
- **Bootstrap integration**: `talos/bootstrap.sh` pushes cereal secrets (`push --cluster cereal`) during full rebuilds; `oracle/bootstrap.sh` pushes oracle secrets (`push --cluster oracle`).
- **Never create K8s secrets manually** with ad-hoc `kubectl create secret` — always go through the CLI so secrets are reproducible from the repo.
- **Template**: New secrets should be documented in `talos/secrets.yaml.template` under the `kubernetes.secrets` example section.
