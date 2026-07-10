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
