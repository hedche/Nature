# Oracle cluster (OCI free-tier K3s)

A second GitOps Kubernetes cluster for the Nature homelab, running on Oracle Cloud
Infrastructure's Always Free ARM tier (`VM.Standard.A1.Flex`). This directory holds
both the Terraform that provisions the cluster **and** its Flux sync tree, so the
whole cluster is self-contained here.

- **Compute**: 1 control plane (1 OCPU / 6 GB / 60 GB boot) + 1 worker (3 OCPUs /
  18 GB / 140 GB boot), ARM64 free tier — the full 4 OCPU / 24 GB / 200 GB
  allocation. K3s with the built-in Traefik ingress, Flannel CNI, and local-path
  storage. Boot volume sizes are declared in Terraform (`*_boot_volume_gb`).
- **Flux**: each cluster runs its own Flux. This one reconciles **`./oracle/flux`**
  (cereal reconciles `./kubernetes/flux`), so the two never deploy each other's apps.
- **Secrets**: shared with cereal via the single `secrets.yaml`. See below.

> Originally adopted from the standalone `~/dv/oci-k8s-terraform` repo, then rebuilt
> clean from this repo's templates (`terraform destroy && terraform apply`) so the
> live cluster matches the tracked config exactly. Do not run Terraform from the old
> repo anymore (split-brain risk).

## Spin up from scratch (day 0)

The whole cluster is declarative — these steps take you from nothing to a
GitOps-managed cluster. Run everything from this `oracle/` directory.

```bash
cd oracle
direnv allow                       # exports KUBECONFIG=./kubeconfig.yaml (one-time)
```

**1. Provide credentials.** Copy the example and fill in your OCI auth + SSH key:

```bash
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars           # tenancy/user OCID, fingerprint, region, ssh_public_key
```

**2. Provision the infrastructure.** This creates the VCN/subnet/security list and
both ARM nodes (control plane 60 GB, worker 140 GB boot volumes — the full 200 GB
free-tier allowance):

```bash
terraform init
terraform apply                    # ~3-5 min; prints the node public IPs at the end
```

> **First boot takes two reboots per node.** Oracle Linux 8 boots with cgroup v1,
> which the K3s kubelet (v1.34+) refuses. cloud-init's `bootcmd` switches each node
> to cgroup v2 and reboots *before* installing K3s, and `oci-growfs` expands the
> root filesystem to fill the larger boot volume. Allow ~5 min after `apply` before
> the API answers. (See Troubleshooting if a node never becomes ready.)

**3. Fetch the kubeconfig.** Wait for the control plane API, then pull its
kubeconfig and rewrite the server address to the public IP:

```bash
CP=$(terraform output -raw control_plane_public_ip)
until curl -k -s --connect-timeout 5 "https://$CP:6443/ping" >/dev/null; do sleep 15; done
ssh opc@"$CP" 'sudo cat /etc/rancher/k3s/k3s.yaml' > kubeconfig.yaml
sed -i '' "s#https://127.0.0.1:6443#https://$CP:6443#g" kubeconfig.yaml   # macOS sed
kubectl get nodes -o wide           # both nodes should reach Ready
```

**4. Bootstrap Flux + secrets.** Pushes this cluster's secrets and installs Flux,
which then reconciles `./oracle/flux`:

```bash
./bootstrap.sh
./bootstrap.sh status               # gitrepository + kustomization should be READY=True
```

That's it — the cluster is up and Flux is managing it. Add apps as described below.

## Environment (direnv)

`cd oracle/` auto-loads `KUBECONFIG=./kubeconfig.yaml` via `.envrc` (run
`direnv allow` once). `kubeconfig.yaml`, `terraform.tfvars`, and `terraform.tfstate*`
are **gitignored** — they hold credentials/state and must never be committed.

If the kubeconfig is missing, fetch it from the control plane and rewrite the server
address to the public IP:

```bash
terraform output -raw control_plane_public_ip   # e.g. 132.145.47.40
ssh opc@<public-ip> 'sudo cat /etc/rancher/k3s/k3s.yaml' > kubeconfig.yaml
# then replace 127.0.0.1 in kubeconfig.yaml with <public-ip>
```

## Terraform

```bash
cd oracle
terraform init     # providers are pinned in .terraform.lock.hcl
terraform plan
terraform apply    # provisions both nodes from the cloud-init templates
```

`terraform.tfvars` carries the OCI auth (tenancy/user OCID, fingerprint, region,
SSH key) and references the API private key at `~/.oci/...` (kept outside the repo).
Copy `terraform.tfvars.example` if you need to recreate it.

The cluster is provisioned entirely from this directory — compute shape, boot
volume sizes (`*_boot_volume_gb`), networking, and cloud-init are all declared, so
`terraform apply` from a clean slate yields a fully working cluster. A `terraform
apply` that would *replace* the instances rebuilds both nodes (new public IPs, new
kubeconfig); fetch the kubeconfig again afterwards (see above) and re-run
`./bootstrap.sh`.

## Bootstrap Flux + secrets

```bash
./bootstrap.sh            # push secrets (--cluster oracle) + install Flux + report
./bootstrap.sh secrets    # push this cluster's secrets only
./bootstrap.sh flux       # install/refresh Flux only
./bootstrap.sh status     # show reconciliation status
```

`bootstrap.sh` pushes secrets with `scripts/secrets.sh push --cluster oracle` (shared
entries like `flux-system` plus anything tagged `clusters: [oracle]`), then applies
`flux/flux-system/` (components, then the `GitRepository` + root `Kustomization`).

## Adding apps

1. Add manifests under `oracle/` (or reference shared ones under `kubernetes/`).
2. Add a Flux `Kustomization` (e.g. `oracle/flux/<app>.yaml`) pointing at the path.
3. List it in `oracle/flux/kustomization.yaml`.
4. App secrets: add to `secrets.yaml` tagged `clusters: [oracle]`, then
   `./bootstrap.sh secrets`.

Note: K3s has no rook-ceph — use the `local-path` storage class, not `ceph-block`.

## Troubleshooting

**K3s crash-loops with "kubelet is configured to not run on a host using cgroup
v1".** The node is still on cgroup v1. cloud-init normally fixes this on first
boot, but if you're recovering a node by hand:

```bash
ssh opc@<node-ip> 'sudo grubby --update-kernel=ALL --args="systemd.unified_cgroup_hierarchy=1" && sudo reboot'
# verify after reboot:
ssh opc@<node-ip> 'test -f /sys/fs/cgroup/cgroup.controllers && echo cgroup-v2-active'
```

**Worker never joins the cluster.** The worker's cloud-init waits up to 10 min for
the control plane API; if the control plane was unhealthy during that window the
agent install is skipped and `k3s-agent.service` won't exist. Install it manually
once the control plane is healthy:

```bash
CP_PRIV=$(terraform output -raw control_plane_private_ip)
TOKEN=$(ssh opc@$(terraform output -raw control_plane_public_ip) 'sudo cat /var/lib/rancher/k3s/server/node-token')
ssh opc@$(terraform output -raw worker_public_ip) \
  "curl -sfL https://get.k3s.io | K3S_URL='https://$CP_PRIV:6443' K3S_TOKEN='$TOKEN' sh -s - agent --node-name k3s-worker"
```

**Boot volume didn't grow.** Confirm the resize landed and the filesystem filled
it: `lsblk -d -o NAME,SIZE` (should show the full size) and `df -h /`. Re-run
`sudo /usr/libexec/oci-growfs -y` if the filesystem is smaller than the disk.
