# Nature

Infrastructure-as-Code for the Nature homelab. A single-secrets-file approach to declarative infrastructure: this repo + one `secrets.yaml` = a fully reproducible Kubernetes cluster.

## Architecture

```
                    ┌──────────────────┐
                    │   Control Plane   │
                    │   10.30.1.50     │
                    │  (Laptop / Talos) │
                    └────────┬─────────┘
                             │
           ┌─────────────────┼─────────────────┐
           │                 │                 │
    ┌──────▼──────┐  ┌──────▼──────┐  ┌──────▼──────┐
    │  Worker 1   │  │  Worker 2   │  │  Worker 3   │
    │  10.30.1.51 │  │  10.30.1.52 │  │  10.30.1.53 │
    └─────────────┘  └─────────────┘  └─────────────┘

    ┌──────────────────┐    ┌──────────────────┐
    │   QNAP NAS       │    │   Raspberry Pi   │
    │   (Storage)      │    │   (Home Assistant)│
    └──────────────────┘    └──────────────────┘
```

## Active Infrastructure

| Component | Role | Address |
|-----------|------|---------|
| Talos Control Plane | Kubernetes control plane | `10.30.1.50` |
| Talos Worker 1 | Kubernetes worker | `10.30.1.51` |
| Talos Worker 2 | Kubernetes worker | `10.30.1.52` |
| Talos Worker 3 | Kubernetes worker | `10.30.1.53` |
| QNAP NAS | Network-attached storage | DHCP (nature.leafbit.uk) |
| Raspberry Pi | Home Assistant | DHCP (nature.leafbit.uk) |

## Quick Start

1. **Install dependencies:**
   ```bash
   # macOS
   brew install talosctl yq

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

4. **Apply to nodes:**
   ```bash
   # Control plane
   talosctl apply-config --insecure --nodes 10.30.1.50 --file talos/generated/controlplane.yaml

   # Workers
   talosctl apply-config --insecure --nodes 10.30.1.51 --file talos/generated/worker.yaml
   talosctl apply-config --insecure --nodes 10.30.1.52 --file talos/generated/worker.yaml
   talosctl apply-config --insecure --nodes 10.30.1.53 --file talos/generated/worker.yaml
   ```

## Directory Layout

```
.
├── .gitignore                # Blocks secrets and generated configs
├── AGENTS.md                 # Conventions for AI agents working on this repo
├── README.md                 # This file
├── secrets.yaml              # Your local secrets (gitignored, never commit)
├── talos/
│   ├── README.md             # Talos-specific docs
│   ├── controlplane.yaml     # Control plane template
│   ├── worker.yaml           # Worker template
│   ├── talosconfig.template  # talosctl client config template
│   ├── secrets.yaml.template # Schema for secrets.yaml
│   ├── generate-configs.sh   # Script: templates + secrets -> runnable configs
│   └── generated/            # Output directory (gitignored)
├── kubernetes/               # Kubernetes manifests (future)
├── home-assistant/           # Home Assistant docs (future)
├── scripts/                  # Utility scripts
└── deprecated/               # Historical configs (not in active use)
```

## Security Notes

- **Never commit `secrets.yaml`** — it is gitignored by default.
- **Back up `secrets.yaml` encrypted** (e.g. age, gpg, 1Password).
- **Old secrets are in git history** — this repo previously contained plaintext secrets. You must rotate all Talos secrets (`talosctl gen secrets`) before the templates are safe to use.
- **Generated configs are gitignored** — `talos/generated/` contains real credentials.

## Deprecated Infrastructure

Old Ubuntu server configs (`blackhole/`, `cloudmon/`, `habitat/`, etc.) have been moved to `deprecated/`. These are no longer maintained. See `deprecated/README.md` for details.

