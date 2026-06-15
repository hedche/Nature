# Oracle cluster (OCI free-tier K3s)

A second GitOps Kubernetes cluster for the Nature homelab, running on Oracle Cloud
Infrastructure's Always Free ARM tier (`VM.Standard.A1.Flex`). This directory holds
both the Terraform that provisions the cluster **and** its Flux sync tree, so the
whole cluster is self-contained here.

- **Compute**: 1 control plane + 1 worker (ARM64, free tier), K3s with the built-in
  Traefik ingress, Flannel CNI, and local-path storage.
- **Flux**: each cluster runs its own Flux. This one reconciles **`./oracle/flux`**
  (cereal reconciles `./kubernetes/flux`), so the two never deploy each other's apps.
- **Secrets**: shared with cereal via the single root `secrets.yaml`. See below.

> Adopted from the standalone `~/dv/oci-k8s-terraform` repo. The Terraform state was
> copied in so we manage the **already-running** cluster — do not run Terraform from
> the old repo anymore (split-brain risk).

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

## Terraform (manage the existing cluster)

```bash
cd oracle
terraform init     # providers are pinned in .terraform.lock.hcl
terraform plan
```

`terraform.tfvars` carries the OCI auth (tenancy/user OCID, fingerprint, region,
SSH key) and references the API private key at `~/.oci/...` (kept outside the repo).
Copy `terraform.tfvars.example` if you need to recreate it.

> **Known drift**: `terraform plan` currently shows the two instances *would be
> replaced* because their live cloud-init `user_data` predates edits to the
> `cloud-init/*.tpl` templates. This drift is inherited from the source repo (the
> live nodes were built from an older template). **Do not `terraform apply`** unless
> you intend to rebuild both nodes (new instances, new public IPs, new kubeconfig).
> Adopting + running Flux does not require apply — the cluster is already up.

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
4. App secrets: add to root `secrets.yaml` tagged `clusters: [oracle]`, then
   `./bootstrap.sh secrets`.

Note: K3s has no rook-ceph — use the `local-path` storage class, not `ceph-block`.
