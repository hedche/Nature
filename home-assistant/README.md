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
  expected, condition icon. Fed by the Met Office integration through
  the template sensors in `ha-config/packages/nature_panel.yaml`.
- **Music** — bedroom Sonos: track/artist, prev/play-pause/next, volume.

The screen dims after 45 s idle and switches off after 5 min; any touch
wakes it. The three relay outputs (86-box mains switching) are exposed
to HA as switches but unused.

### Met Office integration (manual, one-time)

1. Create a free account at <https://datahub.metoffice.gov.uk> and
   subscribe to the **Site-Specific** forecast (free tier, ~360
   calls/day).
2. HA → Settings → Integrations → add **Met Office**, paste the API key.
   The home zone coordinates are used (BA5 1GU ≈ 51.209, −2.647).
3. Check the created weather entity ID. If it isn't
   `weather.met_office_wells`, update it in
   `ha-config/packages/nature_panel.yaml` and in the `weather_entity`
   substitution in `esphome/bedroom-panel.yaml`.
4. Verify hourly rain data: Developer Tools → Actions →
   `weather.get_forecasts` with `type: hourly` — entries should include a
   non-null `precipitation` field (mm).

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
