# Home Assistant — Agent Conventions

Home Assistant OS runs on the Raspberry Pi `hassio` (`10.30.1.60`). This
directory holds the repo-managed parts: ESPHome device configs and HA
config packages. Global secrets rules in the root `AGENTS.md` apply.

## ESPHome (`esphome/`)

- Device YAMLs are committed with `!secret` references only. The real
  values live under the `esphome:` key of the out-of-repo secrets file;
  `esphome/run.sh` renders them into `esphome/secrets.yaml` (gitignored)
  before every build. Never write that file by hand and never commit it.
- **Build and flash from the Mac with the esphome CLI via `run.sh`** —
  never adopt repo-managed devices into the ESPHome add-on dashboard on
  `hassio`. The Pi 4 OOMs on LVGL-sized builds, and adoption would fork
  config ownership. The repo is the single source of truth.
- Pin the CLI to the add-on's version (`uv tool install esphome==2026.7.4`)
  so firmware versions stay consistent with the Atom Echo managed there.
- First flash is over USB-C; subsequent flashes are OTA (`run.sh` handles
  both — esphome picks the transport automatically).
- Entity IDs and device names go in `substitutions:` at the top of each
  device YAML, not inline in lambdas/widgets.

## HA config packages (`ha-config/`)

- `ha-config/packages/*.yaml` are HA "packages" deployed to
  `/config/packages/` on `hassio` by `ha-config/deploy.sh` (scp + `ha core
  check` + `ha core restart`). The Supervisor/Core HTTP API 401s with the
  addon token — SSH as `root@10.30.1.60` is the reliable path.
- `configuration.yaml` on the host must contain
  `homeassistant: packages: !include_dir_named packages` — deploy.sh
  verifies this and refuses to guess if it's missing (manual one-time edit;
  merge under the existing `homeassistant:` key, never add a duplicate).
- UI-configured integrations (Met Office, Sonos, …) can't live in the repo;
  document their manual setup steps in `README.md` instead.
