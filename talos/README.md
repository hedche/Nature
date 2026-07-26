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
├── manifests/                # Post-bootstrap patches to Talos-managed manifests
│   └── coredns-spread.yaml   # Hard anti-affinity so CoreDNS never single-homes
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
- `secrets.yaml` — Your populated secrets file at `~/.config/nature/secrets.yaml` (see below)

## Quick Start — Full Cluster Bootstrap

```bash
# 1. Set up secrets (first time only — see "Setting Up Secrets" below)
cp talos/secrets.yaml.template ~/.config/nature/secrets.yaml

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
cp talos/secrets.yaml.template ~/.config/nature/secrets.yaml
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

Secrets live in a single `secrets.yaml` at `~/.config/nature/secrets.yaml` —
deliberately outside the repo, which is public, so the file cannot be committed
by accident. Back it up with `./scripts/secrets-crypto.sh -e` (age passphrase
encryption, with an offer to move the `.age` file to iCloud). To reproduce the
cluster from scratch, place `secrets.yaml` at `~/.config/nature/` and run
`./talos/generate-configs.sh` followed by `./talos/bootstrap.sh`.

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

## CoreDNS Availability (`manifests/coredns-spread.yaml`)

Talos manages CoreDNS as a bootstrap manifest with 2 replicas and only a **soft**
anti-affinity, so both replicas can land on one node — and they did, both on `cereal`,
because it runs at ~12% of its CPU requests while `snap`/`pop` sit at ~94%/90% and the
scheduler prefers the emptiest node. When cereal's battery ran flat on 2026-07-26
(it is a laptop — see `../HARDWARE.md`) **all** cluster DNS went with it: every pod
failed to resolve internal *and* external names, which shows up in Radarr/Prowlarr as
`Resource temporarily unavailable (…)` and "all indexers unavailable".

`manifests/coredns-spread.yaml` makes the spread mandatory (3 replicas, hard hostname
anti-affinity), so any single node can be lost without losing DNS:

```sh
kubectl -n kube-system patch deploy coredns --patch-file manifests/coredns-spread.yaml
kubectl -n kube-system get pods -l k8s-app=kube-dns -o wide   # expect one per node
```

Re-apply after `talosctl upgrade-k8s`, which re-renders the stock manifest. Note this
mitigates DNS only — `cereal` is still the **single control plane**, so losing it still
means no API server, no `kubectl`, and no scheduling.

With the API server down you can still drive the media stack over its REST APIs, since the
pods keep running on the workers and stay reachable on their `ts.net` URLs. The keys are in
`secrets.yaml`, not only in the pods:

```sh
KEY=$(yq -r '(.kubernetes.secrets[] | select(.name == "media-secrets")).data.RADARR__AUTH__APIKEY' \
      ~/.config/nature/secrets.yaml)
curl -H "X-Api-Key: $KEY" https://radarr.tail0a6fa.ts.net/api/v3/health
curl -X POST -H "X-Api-Key: $KEY" https://radarr.tail0a6fa.ts.net/api/v3/indexer/testall
```

`indexer/testall` reports the real underlying error rather than the vague UI banner, and
`/api/v3/log?...&sortDirection=ascending&level=error` finds when an incident started.

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
talosctl gen secrets -o ~/.config/nature/secrets.yaml
./talos/generate-configs.sh
./talos/bootstrap.sh
```

> **History audited 2026-07-25 — no credentials found.** An earlier revision of
> this file warned that "the old secrets from the original repo are in git
> history". That is not true of this repository. Its history is continuous back
> to the initial commit (2021-10-12), and `talos/controlplane.yaml` and
> `talos/worker.yaml` were first added in `5d8746e` already templated with
> `${PLACEHOLDER}` variables — the plaintext versions they replaced lived only
> in the local working tree and were never committed. The live Talos client
> credential in `talos/talosconfig` does not appear in any commit, reachable or
> otherwise.
>
> Verified four ways: `gitleaks` over all commits, a path audit of every file
> ever added, a binary-safe entropy sweep of every blob, and GitHub's own secret
> scanning of the remote. Every hit was a placeholder or a public identifier
> (Terraform `zh:`/`h1:` lock hashes, a Talos image-factory schematic ID, LVM
> UUIDs, and Talos' documented `--- EXAMPLE KEY ---` / `z01mye6j…` examples).
>
> This cannot speak for any repository that was deleted or force-pushed before
> the audit. If Talos credentials were ever exposed elsewhere, rotate with the
> commands above.
