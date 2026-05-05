# Talos Configuration

This directory contains Talos Linux configuration templates for the Nature Kubernetes cluster.

## Directory Layout

```
talos/
├── controlplane.yaml         # Template for control plane node (with placeholders)
├── worker.yaml               # Template for worker nodes (with placeholders)
├── talosconfig.template      # Template for talosctl client config (with placeholders)
├── .envrc                    # direnv: auto-sets TALOSCONFIG when you cd here
├── secrets.yaml.template     # Schema for your local secrets.yaml
├── generate-configs.sh       # Script to inject secrets into templates
├── generated/                # Output directory for runnable configs (gitignored)
└── README.md                 # This file
```

## Prerequisites

- `talosctl` — Talos CLI ([install guide](https://www.talos.dev/v1.9/introduction/getting-started/))
- `yq` — YAML processor (Go version, `brew install yq` or `go install github.com/mikefarah/yq/v4@latest`)
- `secrets.yaml` — Your populated secrets file at repo root (copy from `secrets.yaml.template`)

## Generating Configs

1. Copy the template and fill in your secrets:
   ```bash
   cp talos/secrets.yaml.template secrets.yaml
   # Edit secrets.yaml with your values (or use `talosctl gen secrets -o secrets.yaml`)
   ```

2. Generate runnable configs:
   ```bash
   ./talos/generate-configs.sh
   ```

3. The script outputs to `talos/generated/`:
   - `controlplane.yaml`
   - `worker.yaml`
   - `talosconfig`

## Applying Configs

**First control plane node:**
```bash
talosctl apply-config --insecure --nodes 10.30.1.50 --file talos/generated/controlplane.yaml
```

**Worker nodes:**
```bash
talosctl apply-config --insecure --nodes 10.30.1.51 --file talos/generated/worker.yaml
talosctl apply-config --insecure --nodes 10.30.1.52 --file talos/generated/worker.yaml
talosctl apply-config --insecure --nodes 10.30.1.53 --file talos/generated/worker.yaml
```

## Rotating Secrets

1. Generate new secrets:
   ```bash
   talosctl gen secrets -o secrets.yaml
   ```

2. Regenerate configs:
   ```bash
   ./talos/generate-configs.sh
   ```

3. Apply to cluster (requires bootstrap):
   ```bash
   talosctl bootstrap --nodes 10.30.1.50
   ```

> ⚠️ **Critical**: The old secrets from the original repo are in git history. Rotate them immediately.
