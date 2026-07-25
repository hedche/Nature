# Proxmox Terraform — agent conventions

- **This directory is the source of truth** for what runs on the Proxmox node `pve`
  (`10.30.1.55`): standalone cloud-init Ubuntu 24.04 VMs, provisioned via the
  `bpg/proxmox` provider. Local Terraform state, no remote backend (mirrors `oracle/`).
- VMs are declared in the `vms` map in `terraform.tfvars` — add/remove an entry and
  `terraform apply`. Per-VM fields override `vm_defaults`. Keep specs modest (node is
  4 threads / 15 GB / ~56 GB `local-lvm`); use IPs `10.30.1.56-.59` (the node is `.55`,
  the k8s nodes are `.50-.53`) on the shared `/24`.
- Auth is a dedicated API token (`terraform@pve`), stored in the `secrets.yaml`
  under the `proxmox:` key and loaded into Terraform via `./.envrc`
  (`TF_VAR_proxmox_api_token`). The token is never committed; `README.md` here
  documents the one-time `pveum` token-creation steps.
- State and `terraform.tfvars` are gitignored — never commit them.
- **Physical disk passthrough** (`data_disk_path`, e.g. the hermes 1TB USB HDD):
  the Proxmox API restricts arbitrary device paths to root, so the attach is a
  one-time root step on pve (`qm set <vmid> --scsi1 /dev/disk/by-id/ata-...,backup=0`);
  terraform then converges without drift. Use the `ata-` by-id alias — the `usb-` one
  contains `:` which the bpg provider cannot parse.
