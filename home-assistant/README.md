# Home Assistant

Home Assistant OS runs on a dedicated Raspberry Pi 4 (`hassio`,
`10.30.1.60`), managed independently of the Talos cluster. This directory
holds the parts that are repo-managed:

```
esphome/                  ESPHome device configs, built/flashed from the Mac
  bedroom-panel.yaml      Guition ESP32-S3-4848S040 4" touch panel (weather + Sonos)
  bedroom-panel-sim.yaml  The same UI in a desktop SDL window, fed mock data
  packages/panel-ui.yaml  The screen itself, shared by the panel and the simulator
  run.sh                  Renders secrets, wraps the esphome CLI
  sim.sh                  Runs / screenshots the simulator
ha-config/
  packages/               HA config packages deployed to /config/packages/
    nature_panel.yaml     Template sensors feeding the bedroom panel
    sleep_sounds.yaml     Bedroom pink-noise / handpan automations
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

### Simulating the panel UI

The panel's screen lives in `packages/panel-ui.yaml`, which both the real
device and `bedroom-panel-sim.yaml` include. The simulator compiles that
same UI into a native macOS binary that draws into an SDL window — real
LVGL, real fonts, real layout — so a change can be seen in ~15s instead of
a 4-minute build and an OTA.

```sh
brew install sdl2                              # one-time
cd home-assistant/esphome
./sim.sh                                       # open the window (Ctrl-C quits)
./sim.sh shot out.png                          # capture one frame and exit
./sim.sh shot music.png -s sim_page music_page # any sim_* value can be overridden
```

`shot` needs Screen Recording permission for your terminal (System
Settings → Privacy & Security → Screen Recording).

It renders the framebuffer and nothing else: backlight brightness, panel
tearing, PSRAM limits and the real touch digitiser are all invisible here
and still need checking on the wall.

## Bedroom panel (Guition ESP32-S3-4848S040)

4" 480×480 IPS touch panel in an 86-box wall-switch form factor. Two
LVGL pages, swipe left/right to switch:

- **Weather** — today's min/max °C, the day's total rain (mm) and the
  next spell of rain, condition icon. Fed by the built-in Met.no
  integration (`weather.forecast_home`, no API key) through the template
  sensors in `ha-config/packages/nature_panel.yaml`. The rain line splits
  the day's wet hours into runs and describes the one still to come —
  `Next: 0.4mm 18:00–20:00`, `Raining: 1.2mm to 16:00`, `No more rain
  today` or `No rain expected` — so a shower that has already passed is
  not merged with one due this evening. A trace below 0.05 mm reads
  `<0.1 mm` rather than rounding down to a dry-looking `0.0`.

  Met.no's hourly forecast contains **only hours still to come**, so the
  mm total is latched against its own previous state and reset at
  midnight, exactly like the min/max temperatures. Without that it decays
  to `0.0` as the day's rain passes and the panel claims a wet morning was
  dry. The latch therefore reads "the wettest the day was ever forecast to
  be", which overstates if a forecast shower is later cancelled — the
  accepted trade for not understating rain that actually fell. True
  fallen-rain totals would need an observation source (a rain gauge);
  Met.no is a forecast service and has none.

  Forecast datetimes must be compared as timestamps, never as ISO
  strings: they carry a UTC offset while `today_at()` renders local, so
  string comparison silently shifts "today" by the local UTC offset (on
  BST it selected 02:00 today → 01:00 tomorrow).
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

Automations moved into a package must be deleted from `/config/automations.yaml`
on hassio in the same change — Core loads both files, and leaving the original
in place registers the automation twice, so one button press fires it twice.
Package automations also stop being editable from the UI; edit them here and
redeploy instead.
