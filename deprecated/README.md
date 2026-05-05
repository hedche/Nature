# Deprecated Infrastructure

This directory contains historical configuration for servers that are no longer part of the active Nature homelab. These files are preserved for reference but should not be used for new deployments.

## Contents

| Item | Description | Why Deprecated |
|------|-------------|----------------|
| `blackhole/` | Ubuntu server setup scripts (192.168.0.x) | Replaced by Talos Kubernetes worker nodes |
| `cloudmon/` | Ubuntu server setup scripts (192.168.0.x) | Replaced by Talos Kubernetes worker nodes |
| `habitat/` | Ubuntu NAS/media server setup (192.168.0.8) | Replaced by QNAP NAS and Kubernetes workloads |
| `proxmox` | Notes for Docker on Debian in LXC containers | No longer using Proxmox for container hosting |
| `git.sh` | Old Git helper script | Replaced by standard git workflows |
| `uni-setup.sh` | Universal server setup script | Replaced by Talos declarative configuration |

## Active Infrastructure

The current homelab runs:
- **Talos Kubernetes**: 1 control plane + 3 workers (10.30.1.x)
- **QNAP NAS**: Network storage
- **Raspberry Pi**: Home Assistant

See the repo root `README.md` and `talos/README.md` for current documentation.
