# Talos Configuration — Cereal Cluster

This directory contains Talos Linux configuration templates for the **cereal** Kubernetes cluster.

## Cluster Overview

| Node | Role | IP | Patch |
|------|------|----|-------|
| (control plane) | controlplane | 10.30.1.50 | — |
| snap | worker | 10.30.1.51 | `patches/snap.yaml` |
| crackle | worker | 10.30.1.52 | `patches/crackle.yaml` |
| pop | worker | 10.30.1.53 | `patches/pop.yaml` |

Cluster endpoint: `https://cereal.nature.leafbit.uk:6443`

## Directory Layout

```
talos/
├── controlplane.yaml         # Template for control plane node (with placeholders)
├── worker.yaml               # Template for worker nodes (with placeholders)
├── talosconfig.template      # Template for talosctl client config (with placeholders)
├── patches/                  # Per-node config patches (merged with worker.yaml)
│   ├── snap.yaml             # snap (worker, 10.30.1.51)
│   ├── crackle.yaml          # crackle (worker, 10.30.1.52) — hostname + disk overrides
│   └── pop.yaml              # pop (worker, 10.30.1.53)
├── bootstrap.sh              # Full cluster bootstrap / per-node apply / status
├── .envrc                    # direnv: auto-sets TALOSCONFIG + KUBECONFIG
├── secrets.yaml.template     # Schema for your local secrets.yaml
├── generate-configs.sh       # Script to inject secrets into templates
├── generated/                # Output directory for runnable configs (gitignored)
└── README.md                 # This file
```

## Prerequisites

- `talosctl` — Talos CLI ([install guide](https://www.talos.dev/v1.9/introduction/getting-started/))
- `yq` — YAML processor (Go version, `brew install yq` or `go install github.com/mikefarah/yq/v4@latest`)
- `kubectl` — Kubernetes CLI
- `secrets.yaml` — Your populated secrets file at repo root (see below)

## Quick Start — Full Cluster Bootstrap

```bash
# 1. Set up secrets (first time only — see "Setting Up Secrets" below)
cp talos/secrets.yaml.template secrets.yaml

# 2. Bootstrap the entire cluster
./talos/bootstrap.sh
```

The bootstrap script generates configs, applies them to all reachable nodes,
bootstraps etcd, fetches the kubeconfig, and reports cluster health.
Offline nodes are skipped — apply them later:

```bash
./talos/bootstrap.sh apply crackle    # single node
./talos/bootstrap.sh status           # cluster health
```

## Setting Up Secrets

Generate fresh Talos secrets and extract them into the template format:

```bash
talosctl gen secrets -o /tmp/talos-secrets.yaml
talosctl gen config cereal https://cereal.nature.leafbit.uk:6443 \
    --with-secrets /tmp/talos-secrets.yaml --output-dir /tmp/talos-gen
cp talos/secrets.yaml.template secrets.yaml
```

Extract each value with `yq`:

```bash
yq '.machine.token'                     /tmp/talos-gen/controlplane.yaml  # → machineToken
yq '.cluster.token'                     /tmp/talos-gen/controlplane.yaml  # → clusterToken
yq '.cluster.id'                        /tmp/talos-gen/controlplane.yaml  # → clusterId
yq '.cluster.secret'                    /tmp/talos-gen/controlplane.yaml  # → clusterSecret
yq '.cluster.secretboxEncryptionSecret' /tmp/talos-gen/controlplane.yaml  # → secretboxEncryptionSecret
yq '.machine.ca'                        /tmp/talos-gen/controlplane.yaml  # → machineCA
yq '.cluster.ca'                        /tmp/talos-gen/controlplane.yaml  # → clusterCA
yq '.cluster.aggregatorCA'              /tmp/talos-gen/controlplane.yaml  # → aggregatorCA
yq '.cluster.etcd.ca'                   /tmp/talos-gen/controlplane.yaml  # → etcdCA
yq '.cluster.serviceAccount.key'        /tmp/talos-gen/controlplane.yaml  # → serviceAccount.key
yq '.contexts.cereal.crt'              /tmp/talos-gen/talosconfig         # → client.crt
yq '.contexts.cereal.key'              /tmp/talos-gen/talosconfig         # → client.key
```

Clean up and generate real configs:

```bash
rm -rf /tmp/talos-secrets.yaml /tmp/talos-gen
./talos/generate-configs.sh
```

## Backing Up & Restoring Secrets

Secrets live in a single `secrets.yaml` at the repo root. Back this file up using
your preferred secure mechanism (e.g., encrypted password-manager export, or
any external secret storage you already trust). To reproduce the cluster from
scratch, place `secrets.yaml` in the repo root and run `./talos/generate-configs.sh`
followed by `./talos/bootstrap.sh`.

## Per-Node Patches

Each worker gets an explicit hostname via a patch in `patches/`.
`generate-configs.sh` merges each `patches/<name>.yaml` with the base
`worker.yaml`, producing `generated/worker-<name>.yaml`.

Example (`patches/crackle.yaml`):

```yaml
machine:
    network:
        hostname: crackle
    disks:
        - deviceSelector:
              match: 'disk.transport == "sata" && !disk.systemDisk && disk.size >= 900u * GB'
          partitions:
              - mountpoint: /var/mnt/storage
```

### Hardware Reference

| Node | Install Disk | Storage Disk |
|------|-------------|-------------|
| control plane | SATA (ata1 bus) | — |
| snap | NVMe (TBD) | TBD |
| crackle | Micron 2200S NVMe 256GB | KIOXIA-EXCERIA S 960GB (SATA) |
| pop | NVMe (TBD) | TBD |

## PXE Recovery Reinstall

The QNAP NAS can serve a PXE recovery menu from `10.30.1.20`; see `../pxe/README.md`.

Default flow:

```bash
./pxe/deploy-to-qnap.sh
# Boot the target node from PXE and select "Talos maintenance mode".
./talos/bootstrap.sh apply <node>
./talos/bootstrap.sh status
```

The default PXE menu does not expose generated Talos machine configs. If you intentionally use unattended reinstall mode, `./pxe/deploy-to-qnap.sh --include-talos-configs` copies files from `talos/generated/` into `pxe/generated/http/configs/` before deploying. Those files contain cluster secrets and should only be served on a trusted provisioning network, then removed by redeploying without that flag.

## Rotating Secrets

```bash
talosctl gen secrets -o secrets.yaml
./talos/generate-configs.sh
./talos/bootstrap.sh
```

> **Critical**: The old secrets from the original repo are in git history. Rotate them immediately.
n git history. Rotate them immediately.
