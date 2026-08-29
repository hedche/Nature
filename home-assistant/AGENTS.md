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

### Bedroom panel — verify in the simulator before flashing

The panel's screen is split so the same UI runs on the Mac as on the wall:

| File | What it holds |
|------|---------------|
| `esphome/packages/panel-ui.yaml` | The UI itself: globals, gesture scripts, `ui_*` data scripts, fonts, LVGL. No hardware, no data sources. |
| `esphome/packages/light-tile.yaml` | One lights-page tile, pulled into the UI package four times with `!include` vars (`n`, `col`, `row`, `icon`, `name`). Edit the tile here, never by copying it. |
| `esphome/bedroom-panel.yaml` | The real Guition 4848S040: hardware, plus the Home Assistant sensors that feed it. |
| `esphome/bedroom-panel-sim.yaml` | The same UI on an SDL window, fed mock `sim_*` values. |

- **Any change to `packages/panel-ui.yaml` must be checked in the simulator
  before it is flashed.** `./sim.sh shot out.png` compiles and captures a PNG
  of the actual rendered screen in ~15s (vs ~4min + an OTA) — then look at the
  PNG. `./sim.sh` on its own opens the window interactively.
- Data reaches the UI **only** through the `ui_*` scripts. A new value means:
  add a `ui_*` script in the UI package, then call it from *both*
  `bedroom-panel.yaml` (a sensor's `on_value`) and `bedroom-panel-sim.yaml`
  (its `on_boot` block). Skip the sim side and the simulator quietly renders a
  stale screen — that divergence is the main failure mode of this split.
- The two targets must keep providing the IDs the UI package addresses:
  `lcd`, `panel_touch`, `backlight`, `panel_restart`, `${sonos_entity}`,
  and `${light_N_entity}` / `${light_N_name}` / `${light_N_icon}` for
  N = 1..4. An icon must be in the package's `mdi_42` glyph list — a glyph
  the font was not built with renders as a box, not an error.
- Exercise edge cases with substitutions, not by editing files:
  `./sim.sh shot long.png -s sim_media_title "a 90-character track name…"`.
- Some states are reachable only via a substitution, and all are easy to
  assume are untestable:
  - `-s sim_drawer true` opens the settings drawer. It lives on the LVGL top
    layer rather than being a page, so `sim_page` cannot select it and
    `./sim.sh shot` would otherwise never photograph it.
  - `-s sim_temp_min NAN` (uppercase — lowercase `nan` will not compile)
    reproduces an unavailable Home Assistant sensor, which is what the panel
    shows after every HA restart.
  - `-s sim_light_N unavailable` renders a dead light tile; `-s sim_pressed
    true` forces the first tile and the All-off bar into LVGL's pressed
    state, since a `shot` has no finger on the screen.
- **What the simulator cannot tell you:** it renders LVGL's framebuffer, so it
  has nothing to say about backlight brightness (the `backlight` output is a
  logging stub), RGB panel tearing, PSRAM pressure, boot behaviour or the real
  touch digitiser. Those still need the panel on the wall.
- `sim.sh` needs SDL2 (`brew install sdl2`). `shot` needs nothing else: the
  simulator is compiled with `sim_shot` set to a BMP path, runs on SDL's
  dummy video driver, writes its own backbuffer there (`sim_shot.h`) and
  exits — headless, sandbox-safe, and it never captures the wrong window.

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
