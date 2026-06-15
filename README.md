# Nature

Infrastructure-as-Code for the Nature homelab. A single-secrets-file approach to declarative infrastructure: this repo + one `secrets.yaml` = a fully reproducible Kubernetes cluster.

## Architecture

```
                    ┌──────────────────┐
                    │     cereal       │
                    │   10.30.1.50     │
                    │  (control plane) │
                    └────────┬─────────┘
                             │
           ┌─────────────────┼─────────────────┐
           │                 │                 │
    ┌──────▼──────┐  ┌──────▼──────┐  ┌──────▼──────┐
    │    snap      │  │   crackle   │  │     pop     │
    │  10.30.1.51 │  │  10.30.1.52 │  │  10.30.1.53 │
    │  (worker)   │  │  (worker)   │  │  (worker)   │
    └─────────────┘  └─────────────┘  └─────────────┘

    ┌──────────────────┐    ┌──────────────────┐    ┌──────────────────┐
    │    QNAP NAS      │    │     arctic       │    │     hassio       │
    │   10.30.1.20     │    │   10.30.1.21     │    │   10.30.1.60     │
    │ (storage / PXE)  │    │ (WD MyCloud NAS) │    │ (Home Assistant) │
    └──────────────────┘    └──────────────────┘    └──────────────────┘

                    ┌──────────────────┐
                    │     photon       │
                    │   10.30.1.90     │
                    │ (Raspberry Pi 3A+)│
                    └──────────────────┘
```

## Active Infrastructure

| Hostname | Role | Address |
|----------|------|---------|
| `cereal` | Talos control plane | `10.30.1.50` |
| `snap` | Talos worker | `10.30.1.51` |
| `crackle` | Talos worker | `10.30.1.52` |
| `pop` | Talos worker | `10.30.1.53` |
| `photon` | Raspberry Pi 3A+ — CUPS | `10.30.1.90` |
| `qnap` | QNAP NAS — network-attached storage, PXE recovery server | `10.30.1.20` |
| `arctic` | WD MyCloud NAS 2TB | `10.30.1.21` |
| `hassio` | Raspberry Pi 4B 4GB RAM — Home Assistant | `10.30.1.60` |

Two GitOps-managed Kubernetes clusters:

| Cluster | Type | Location | Flux sync path |
|---------|------|----------|----------------|
| **cereal** | Talos | on-prem (`cereal.nature.leafbit.uk:6443`) | `./kubernetes/flux` |
| **oracle** | K3s | Oracle Cloud free tier (ARM, public IP) | `./oracle/flux` |

Each cluster runs its own Flux that reconciles only its own path, so apps never
cross between clusters. See `oracle/README.md` for the OCI cluster.

## Quick Start

1. **Install dependencies:**
   ```bash
   # macOS
   brew install talosctl yq kubectl

   # Linux
   curl -sL https://talos.dev/install | sh
   # yq: https://github.com/mikefarah/yq/releases
   ```

2. **Create your secrets file:**
   ```bash
   cp talos/secrets.yaml.template secrets.yaml
   # Edit secrets.yaml and fill in your values
   # OR generate fresh secrets:
   talosctl gen secrets -o secrets.yaml
   ```

3. **Generate Talos configs:**
   ```bash
   ./talos/generate-configs.sh
   ```

4. **Bootstrap the cluster:**
   ```bash
   ./talos/bootstrap.sh            # Full cluster bootstrap
   ./talos/bootstrap.sh apply snap # Apply config to a single node
   ./talos/bootstrap.sh status     # Check cluster health
   ```

## Oracle (OCI) cluster

A second cluster — a free-tier K3s cluster on Oracle Cloud — lives under `oracle/`
(Terraform for the infra + its own Flux sync tree). `cd oracle/` auto-loads its
`KUBECONFIG` via direnv.

Two `VM.Standard.A1.Flex` ARM64 instances (Oracle Linux 8), sized to the Always
Free allocation of 4 OCPUs / 24 GB RAM:

| Node | Role | OCPUs | RAM | Boot volume |
|------|------|-------|-----|-------------|
| `k3s-control-plane` | K3s server | 1 | 6 GB | 60 GB |
| `k3s-worker` | K3s agent | 3 | 18 GB | 140 GB |
| **Total** | | **4** | **24 GB** | **200 GB** (full free-tier allowance) |

This consumes the entire Always Free allocation (4 OCPUs / 24 GB RAM / 200 GB block
storage). Boot volume sizes are declared in Terraform (`*_boot_volume_gb`) and
weighted toward the worker, where workloads and their `local-path` PVs land;
cloud-init runs `oci-growfs` so each node's root filesystem fills its volume.
Storage is the K3s built-in `local-path` provisioner — there is no rook-ceph here.
CNI is Flannel and ingress is the built-in Traefik.

To spin it up from scratch (provision → kubeconfig → Flux):

```bash
cd oracle
direnv allow                       # exports KUBECONFIG=./kubeconfig.yaml
cp terraform.tfvars.example terraform.tfvars   # then fill in OCI auth + SSH key
terraform init && terraform apply  # provisions both nodes (~3-5 min)
# fetch kubeconfig from the new control plane, then:
./bootstrap.sh                     # push secrets (--cluster oracle) + install Flux
```

See **[`oracle/README.md`](oracle/README.md)** for the full step-by-step day-0
guide (including fetching the kubeconfig and the cgroup v2 first-boot behaviour)
and troubleshooting.

Secrets are shared with cereal via the single root `secrets.yaml`. Entries tagged
`clusters: [cereal]` stay on cereal; untagged entries (e.g. `flux-system`) are
shared.

## PXE Recovery

The QNAP NAS at `10.30.1.20` can run a containerized PXE recovery service for Talos reinstall/maintenance boots.

```bash
./pxe/deploy-to-qnap.sh
./pxe/test-pxe.sh
```

By default, PXE boots Talos into maintenance mode and does **not** serve generated Talos configs. Unattended reinstall is available with an explicit opt-in flag; see `pxe/README.md`.

## Directory Layout

```
.
├── .gitignore                # Blocks secrets and generated configs
├── AGENTS.md                 # Conventions for AI agents working on this repo
├── README.md                 # This file
├── secrets.yaml              # Your local secrets (gitignored, never commit)
├── ansible/
│   ├── inventory.yml         # Ansible host inventory (photon)
│   ├── photon.yml            # Playbook for Raspberry Pi setup
│   └── roles/                # Ansible roles (cups_server, etc.)
├── talos/
│   ├── README.md             # Talos-specific docs
│   ├── controlplane.yaml     # Control plane config template
│   ├── worker.yaml           # Worker config template
│   ├── patches/              # Per-node worker patches (snap, crackle, pop)
│   ├── talosconfig.template  # talosctl client config template
│   ├── secrets.yaml.template # Schema for secrets.yaml
│   ├── generate-configs.sh   # Script: templates + secrets -> runnable configs
│   ├── bootstrap.sh          # Full cluster bootstrap script
│   └── generated/            # Output directory (gitignored)
├── kubernetes/               # cereal cluster manifests + Flux sync (./kubernetes/flux)
├── oracle/                   # Oracle (OCI) K3s cluster: Terraform infra + Flux sync (./oracle/flux)
│   ├── *.tf, cloud-init/     # Terraform: provisions the free-tier ARM K3s cluster
│   ├── .envrc                # direnv: exports KUBECONFIG for this cluster
│   ├── bootstrap.sh          # Push secrets + install Flux onto the cluster
│   └── flux/                 # Flux sync tree (flux-system + app Kustomizations)
├── home-assistant/           # Home Assistant docs (future)
├── pxe/                      # QNAP-hosted PXE recovery service
├── scripts/                  # Utility scripts (secrets.sh — cluster-aware)
└── deprecated/               # Historical configs (not in active use)
```

## Security Notes

- **Never commit `secrets.yaml`** — it is gitignored by default.
- **Back up `secrets.yaml` securely** — use your preferred encrypted password-manager export or any external secret storage you already trust.
- **Generated configs are gitignored** — `talos/generated/`, `talos/kubeconfig`, and `talos/talosconfig` all contain real credentials.
- **PXE generated assets are gitignored** — `pxe/generated/` may contain copied Talos machine configs when unattended reinstall mode is used.
- All Talos config templates use `${PLACEHOLDER}` variables — no secrets are stored in tracked files.

## Deprecated Infrastructure

Old Ubuntu server configs (`blackhole/`, `cloudmon/`, `habitat/`, etc.) have been moved to `deprecated/`. These are no longer maintained. See `deprecated/README.md` for details.
