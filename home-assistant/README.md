# Home Assistant

Home Assistant OS runs on a dedicated Raspberry Pi 4 (`hassio`,
`10.30.1.60`), managed independently of the Talos cluster. This directory
holds the parts that are repo-managed:

```
esphome/                  ESPHome device configs, built/flashed from the Mac
  bedroom-panel.yaml      Guition ESP32-S3-4848S040 4" touch panel (weather + Sonos)
  run.sh                  Renders secrets, wraps the esphome CLI
ha-config/
  packages/               HA config packages deployed to /config/packages/
    nature_panel.yaml     Template sensors feeding the bedroom panel
  deploy.sh               scp package(s) to hassio + ha core check/restart
```

## ESPHome devices

### One-time setup

```sh
brew install yq                          # if not installed
uv tool install esphome==2026.7.4        # pin to the hassio add-on's version
```

Add real values under the `esphome:` key of the secrets file (see
`talos/secrets.yaml.template` for the schema — wifi credentials, an API
encryption key from `openssl rand -base64 32`, an OTA password from
`openssl rand -hex 16`).

### Build & flash

```sh
cd home-assistant/esphome
./run.sh                       # compile + upload bedroom-panel.yaml
./run.sh compile               # compile only
./run.sh logs                  # stream device logs
```

First flash: connect the panel over USB-C (shows up as
`/dev/cu.usbmodem*`; hold BOOT while plugging in if download mode isn't
entered). After that, uploads go OTA automatically.

After the first boot, Home Assistant auto-discovers the device
(Settings → Devices → ESPHome). Add it with the API encryption key, then
on the device page **tick "Allow the device to perform Home Assistant
actions"** — without it every media button on the panel is silently
ignored.

Do not adopt repo-managed devices into the ESPHome add-on dashboard —
see `AGENTS.md`.

## Bedroom panel (Guition ESP32-S3-4848S040)

4" 480×480 IPS touch panel in an 86-box wall-switch form factor. Two
LVGL pages, swipe left/right to switch:

- **Weather** — today's min/max °C, total rain (mm) and when it's
  expected, condition icon. Fed by the built-in Met.no integration
  (`weather.forecast_home`, no API key) through the template sensors in
  `ha-config/packages/nature_panel.yaml`.
- **Music** — bedroom Sonos: track/artist (with stream/filename
  fallbacks), album art (JPEG/PNG via HA's image proxy), prev/play-pause/
  next, volume.

Swipe down from the top edge for the settings drawer: brightness
slider, screen off, restart, wifi signal/IP. Swipe up or tap ✕ to close.

The screen dims after 45 s idle and switches off after 5 min; any touch
wakes it. The three relay outputs (86-box mains switching) are exposed
to HA as switches but unused.

### Weather source

The default Met.no (Meteorologisk institutt) integration supplies the
forecast — no API key, uses the HA home zone coordinates, and its hourly
forecast includes `precipitation` in mm. The entity is
`weather.forecast_home`; if it's ever renamed, update it in
`ha-config/packages/nature_panel.yaml` (3 places) and in the
`weather_entity` substitution in `esphome/bedroom-panel.yaml`.
(The Met Office DataHub integration was considered but its config flow
failed to connect with a fresh API key; Met.no is keyless and sufficient.)

## HA config packages

Deployed over SSH (the Core HTTP API rejects addon tokens):

```sh
cd home-assistant/ha-config
./deploy.sh                    # scp packages/*.yaml, ha core check, restart
```

One-time host prerequisite: `/config/configuration.yaml` must contain

```yaml
homeassistant:
  packages: !include_dir_named packages
```

`deploy.sh` checks for this and tells you if it's missing (edit manually
under the existing `homeassistant:` key — don't add a duplicate key).
