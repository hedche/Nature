# Proxmox node (`pve`) — Terraform-managed VMs

Standalone cloud-init Linux VMs running on the Proxmox VE node `pve` (`10.30.1.55`),
defined declaratively with Terraform and the [`bpg/proxmox`](https://registry.terraform.io/providers/bpg/proxmox/latest)
provider. This directory is the source of truth for what runs on that node.

- **Node**: PVE 9.1.1, Intel i5-5250U (2c/4t), 15 GB RAM, single 119 GB NVMe →
  `local` (dir; ISOs/images via the `import` content type) + `local-lvm` (lvmthin,
  ~56 GB; VM disks). Bridge `vmbr0` @ `10.30.1.55/24`, gateway `10.30.1.1`.
- **Workload**: general-purpose Ubuntu 24.04 VMs (cloud-init). Independent of the k8s
  clusters, though it shares the `10.30.1.0/24` subnet with the Talos `cereal`
  cluster (`10.30.1.50-.53`). These VMs use `10.30.1.56-.59` (node is `.55`).
  - `hermes` (`10.30.1.57`, vmid `157`, 2c/8 GB/40 GB): bare host for the Nous Research
    [Hermes Agent](https://github.com/nousresearch/hermes-agent). Terraform only provisions
    the VM + injects the SSH key; Hermes itself is installed manually on the guest.
- **State**: local Terraform state, no remote backend (mirrors `oracle/`).

> Capacity is modest (4 threads / 15 GB / ~56 GB `local-lvm`). Realistically this is
> 1–3 small VMs. Keep `vm_defaults` lean and avoid heavy core overcommit.

## One-time Proxmox setup

Create a dedicated, least-privilege API token for Terraform. Run on the node as root:

```bash
ssh pve

pveum role add TerraformProv -privs "VM.Allocate VM.Clone VM.Config.CDROM VM.Config.CPU \
  VM.Config.Cloudinit VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network \
  VM.Config.Options VM.Audit VM.PowerMgmt VM.Console Datastore.Allocate \
  Datastore.AllocateSpace Datastore.AllocateTemplate Datastore.Audit SDN.Use Sys.Audit \
  Sys.Console Sys.Modify Pool.Allocate"

pveum user add terraform@pve --comment "Terraform provisioning"
pveum acl modify / --user terraform@pve --role TerraformProv

# Prints the token UUID ONCE — capture it now.
pveum user token add terraform@pve terraform --privsep 0
```

- `SDN.Use` is required on PVE 9.x to attach a NIC to `vmbr0`.
- `--privsep 0` lets the token inherit the user's role (simplest for a homelab).
  With `--privsep 1` you must additionally grant the token its own ACL:
  `pveum acl modify / --token 'terraform@pve!terraform' --role TerraformProv`.

The full token string is `terraform@pve!terraform=<UUID>`.

> Only needed if you later use **custom** cloud-init `user_data` (extra packages,
> `runcmd`, etc.): enable the `snippets` content type on `local`, which is not on
> today — `pvesm set local --content iso,vztmpl,backup,import,snippets`. The default
> `initialization` block (user/keys/IP/DNS) used here does **not** need it.

## Secrets

Record the token and your SSH public key in the root `secrets.yaml` (gitignored)
under a `proxmox:` stanza (schema documented in `talos/secrets.yaml.template`):

```yaml
proxmox:
  api_token: "terraform@pve!terraform=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
  endpoint: "https://10.30.1.55:8006/"
  ssh_public_key: "ssh-ed25519 AAAA... you@host"
```

`./.envrc` (direnv + `yq`) reads those values and exports them as
`TF_VAR_proxmox_api_token` / `TF_VAR_proxmox_endpoint` / `TF_VAR_ssh_public_key`, so
the token never lands in `terraform.tfvars` and the SSH key has a single source of
truth (the key is injected into every VM's cloud-init user). Run `direnv allow` once
after cloning. To override the key per-checkout, set `ssh_public_key` in
`terraform.tfvars` instead.

## Configure & apply

```bash
cd proxmox
direnv allow                          # exports TF_VAR_* from ../secrets.yaml (one-time)

cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars              # set ssh_public_key and the vms map

terraform init                        # downloads bpg/proxmox, writes .terraform.lock.hcl
terraform plan                        # expect 1 download_file + 1 VM per vms entry
terraform apply                       # first run fetches the ~300 MB image, then creates VMs
```

If you did not use `.envrc`, supply the token another way, e.g.
`export TF_VAR_proxmox_api_token='terraform@pve!terraform=<UUID>'`.

## Verify

```bash
terraform output vms                  # vmid + configured IP per VM
ssh pve qm list                       # VMs as Proxmox sees them
ssh ubuntu@10.30.1.56                 # log in (static-IP VM)
#   inside the guest:
cloud-init status --wait              # confirm cloud-init finished
```

For DHCP VMs (no `ip_address`), find the lease on your router, or:
`ssh pve qm guest cmd <vmid> network-get-interfaces` (needs the guest agent).

## Add / remove a VM

Edit the `vms` map in `terraform.tfvars`, then `terraform apply`:

- **Add**: append a new keyed entry (unique `vmid`, IP in `10.30.1.56-.59`).
  Per-VM fields override `vm_defaults`; omit `ip_address` for DHCP.
- **Remove**: delete its key and apply — that VM (only) is destroyed.

## Gotchas

- **bpg is pre-1.0** — the version is pinned (`~> 0.84`); commit `.terraform.lock.hcl`.
- **Self-signed cert** — the provider sets `insecure = true`; without it `init`/`plan`
  fail with x509 errors.
- **SSH to the node** — importing the cloud image to a VM disk (`import_from`) is done
  over SSH, so the provider's `ssh { agent = true, username = "root" }` block needs a
  working key. Ensure your key is loaded (`ssh-add ~/.ssh/id_ed25519`) and authorized
  for `root@10.30.1.55` before `apply`.
- **Guest agent** — `agent.enabled = false` by default. Enabling it makes `apply` wait
  for `qemu-guest-agent` in the guest; the Ubuntu cloud image ships the package but it
  only runs once the VM has the agent channel. Leaving it off keeps `apply` from
  hanging; turn it on once you're confident the agent comes up.
- **Cloud-init drive** — managed by the `initialization` block; don't also hand-attach
  an `ide2` cloud-init drive in Proxmox.
- **Image download** — slow on the first apply (image fetch); subsequent applies are
  fast because `overwrite = false`.
- **VMID/IP collisions** — VMIDs must be ≥ 100; `10.30.1.50-.53` are the k8s nodes and
  `.55` is the node itself. Keep these VMs at `10.30.1.56-.59` (map `.56` → vmid `156`).
