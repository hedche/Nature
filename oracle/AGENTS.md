# Oracle (OCI) Terraform — agent conventions

- **This directory is the source of truth** for the OCI cluster. It was adopted from
  `~/dv/oci-k8s-terraform` by copying the Terraform state in (gitignored). **Do not
  run Terraform from the old repo** — both pointing at the same infra causes
  split-brain. Treat the old repo as archived.
- **Do not `terraform apply` here** unless you intend to rebuild the cluster.
  `terraform plan` shows both instances "must be replaced" because the live nodes'
  cloud-init `user_data` predates edits to `cloud-init/*.tpl` (pre-existing drift,
  identical in the source repo). Applying destroys and recreates both nodes — new
  instances, new public IPs, new kubeconfig. Running Flux/GitOps does **not** require
  apply; the cluster is already up.
- The `oracle` cluster is K3s (Traefik + local-path storage built in); it has **no**
  rook-ceph. Apps needing `ceph-block` storage are cereal-only.
- State, `terraform.tfvars`, and `kubeconfig.yaml` are gitignored — never commit them.
