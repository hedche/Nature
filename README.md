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

    ┌──────────────────┐    ┌──────────────────┐
    │   QNAP NAS       │    │     photon       │
    │   (storage)      │    │   (Raspberry Pi) │
    └──────────────────┘    └──────────────────┘
```

## Active Infrastructure

| Hostname | Role | Address |
|----------|------|---------|
| `cereal` | Talos control plane | `10.30.1.50` |
| `snap` | Talos worker | `10.30.1.51` |
| `crackle` | Talos worker | `10.30.1.52` |
| `pop` | Talos worker | `10.30.1.53` |
| `photon` | Raspberry Pi — Home Assistant, CUPS | `10.30.1.90` |
| QNAP NAS | Network-attached storage | — |

Cluster name: **cereal** — API endpoint: `talos.nature.leafbit.uk:6443`

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
├── kubernetes/               # Kubernetes manifests (future)
├── home-assistant/           # Home Assistant docs (future)
├── scripts/                  # Utility scripts (backup/restore secrets)
└── deprecated/               # Historical configs (not in active use)
```

## Security Notes

- **Never commit `secrets.yaml`** — it is gitignored by default.
- **Back up `secrets.yaml` encrypted** — use `./scripts/backup-secrets.sh` (requires [age](https://github.com/FiloSottile/age)).
- **Generated configs are gitignored** — `talos/generated/`, `talos/kubeconfig`, and `talos/talosconfig` all contain real credentials.
- All Talos config templates use `${PLACEHOLDER}` variables — no secrets are stored in tracked files.

## Deprecated Infrastructure

Old Ubuntu server configs (`blackhole/`, `cloudmon/`, `habitat/`, etc.) have been moved to `deprecated/`. These are no longer maintained. See `deprecated/README.md` for details.

