# Talos configs — agent conventions

- Edit the `.template` versions, not generated configs (`generated/` is gitignored
  output of `generate-configs.sh`).
- Add any new placeholder to `secrets.yaml.template` with a comment explaining how to
  generate it.
- Run `bash -n talos/generate-configs.sh` to check script syntax after changes.
- **Node labels**: worker role labels (`node-role.kubernetes.io/worker`) are applied by
  `bootstrap.sh` (the `apply-labels` command) — don't label nodes manually.
  NodeRestriction admission blocks kubelets from self-assigning `node-role.*` labels,
  which is why they live in the bootstrap script rather than `machine.nodeLabels`.
- `bootstrap.sh` pushes cereal secrets (`scripts/secrets.sh push --cluster cereal`)
  during full rebuilds.
- **`patches/` is worker-only.** `generate-configs.sh` merges every file there into
  `worker.yaml` and emits `worker-<name>.yaml`, and `bootstrap.sh` resolves the control
  plane by the node key `controlplane`, not `cereal`. A `patches/cereal.yaml` would
  silently produce a `worker-cereal.yaml` that nothing ever applies — control-plane
  changes go directly in `controlplane.yaml`, which is safe because there is exactly
  one control-plane node.
- **Applying control-plane changes**: `talosctl apply-config --mode=auto` regenerates the
  static-pod manifests and the kubelet restarts the affected pod in ~15s without a reboot.
  cereal is the *only* control plane, so apply one change at a time and dry-run first.
  Changes to `cluster.etcd` are the exception — they restart the single etcd member and
  make the API server briefly unavailable; take a snapshot first.
