# Home Assistant

Home Assistant OS runs on a dedicated Raspberry Pi 4 (`hassio`,
`10.30.1.60`), managed independently of the Talos cluster. This directory
holds the parts that are repo-managed:

```
esphome/                  ESPHome device configs, built/flashed from the Mac
  bedroom-panel.yaml      Guition ESP32-S3-4848S040 4" touch panel (weather + Sonos + lights)
  bedroom-panel-sim.yaml  The same UI in a desktop SDL window, fed mock data
  packages/panel-ui.yaml  The screen itself, shared by the panel and the simulator
  packages/light-tile.yaml  One lights-page tile, included per light with `!include` vars
  sim_shot.h              Lets the simulator dump its own framebuffer for `sim.sh shot`
  run.sh                  Renders secrets, wraps the esphome CLI
  sim.sh                  Runs / screenshots the simulator
ha-config/
  packages/               HA config packages deployed to /config/packages/
    bedroom_alarm.yaml    Bedroom 08:50 one-shot alarm (button 2 + Sonos)
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

If the OTA step fails instantly with `No route to host` while `nc -z
10.30.1.124 3232` connects, it is macOS Local Network privacy, not the
network: Apple's own binaries are exempt but the uv-installed Python is
silently denied unless the terminal you are in has been granted *Local
Network* (System Settings → Privacy & Security → Local Network). Grant it,
or run the upload from a terminal that has it.


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
./sim.sh shot lights.png -s sim_page lights_page -s sim_light_4 unavailable
```

`shot` runs the simulator headlessly (SDL's dummy video driver) and has it
write its own framebuffer to disk (see `sim_shot.h`) rather than
screenshotting the desktop, so it needs no Screen Recording permission,
opens no window, and works from a sandboxed or SSH shell.

It renders the framebuffer and nothing else: backlight brightness, panel
tearing, PSRAM limits and the real touch digitiser are all invisible here
and still need checking on the wall.

## Bedroom panel (Guition ESP32-S3-4848S040)

4" 480×480 IPS touch panel in an 86-box wall-switch form factor. Three
LVGL pages, swipe left/right to switch:

- **Weather** — today's min/max °C, the day's total rain (mm) and the
  next spell of rain, condition icon. Fed by the built-in Met.no
  integration (`weather.forecast_home`, no API key) through the template
  sensors in `ha-config/packages/nature_panel.yaml`. The rain line splits
  the wet hours into runs and describes the one still to come —
  `Next: 0.4mm 18:00–20:00`, `Raining: 1.2mm to 16:00`, `Tomorrow: 2.1mm
  09:00–13:00`, `No more rain today` or `No rain expected` — so a shower
  that has already passed is not merged with one due this evening. A
  trace below 0.05 mm reads `<0.1 mm` rather than rounding down to a
  dry-looking `0.0`.

  The line looks **one day ahead**. Because the forecast holds only hours
  still to come, a wet morning leaves today with no wet hours left, and a
  today-only version printed `No rain expected` directly beneath a
  latched `16.2 mm rain today`. Once today is dry the line rolls onto
  tomorrow's first wet run; the day after is deliberately out of scope.
  With neither day wet, the latched mm total picks the wording: `No more
  rain today` if it has already rained, `No rain expected` if it never
  will. Run ends come from the next forecast entry rather than
  last-hour + 1 h, since Met.no thins to multi-hour steps further out.

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
- **Lights** — four tiles (Lydia's Light, Stair Light, Kitchen Lamp,
  Bookshelf Lamp — all smart plugs, so plain on/off) and an "All off"
  bar. A tile is amber when the light is on, dark when off, and recedes
  with the word *Unavailable* when HA or the plug is unreachable (also
  what every tile shows until HA has reported, and again the moment the
  HA connection drops). Tapping calls `homeassistant.toggle`; the tile
  only changes once HA reports the new state, so it never lies. Which
  lights, their names and icons are the `light_N_*` substitutions in
  `bedroom-panel.yaml` (icons must be in the package's `mdi_42` glyph
  list). Two guards keep a bedroom panel honest: a swipe that starts and
  ends on the same tile is not a tap, and the touch that wakes a dimmed
  or sleeping screen never toggles what it landed on.

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

## Bedroom wake-up alarm

A short press of **button 2** on the bedroom TS0044 remote arms the alarm for
the next wake-up time, and the bedroom Sonos confirms it out loud — *"Alarm set
for eight fifty A M"* — with *"Alarm turned off for …"* on the press that
disarms it. Everything lives in `ha-config/packages/bedroom_alarm.yaml`: the
`input_boolean.bedroom_alarm` arm flag, the `input_datetime.bedroom_alarm_time`
wake-up time, a `sensor.bedroom_alarm_next` readout, the ring and confirmation
scripts, and the two automations.

The time is set from the **bedroom panel**: the weather page carries an alarm
chip (bell, wake-up time, and whether it is armed) to the left of the weather
icon, and tapping it opens a full-screen editor with +/− buttons that
accelerate as you hold them and an AM/PM toggle. Closing it — the ✕ or a swipe
down — returns to the weather page. It can also be set from a **Bedroom Alarm
card on the Priors Hill dashboard** with a time picker, the arm toggle and the
next-alarm readout:

```yaml
type: entities
title: Bedroom Alarm
show_header_toggle: false
entities:
  - entity: input_datetime.bedroom_alarm_time
    name: Wake-up time
    icon: mdi:clock-outline
  - entity: input_boolean.bedroom_alarm
    name: Armed
    icon: mdi:alarm
  - entity: sensor.bedroom_alarm_next
    name: Next alarm
```

The dashboard is storage-mode, so that card is a manual paste (Priors Hill →
Edit → Raw configuration editor), like the other UI-owned config here.
Toggling the arm flag from the dashboard is deliberately **silent**: the spoken
confirmations hang off the button press, because a phone tap should not fire
the bedroom speaker.

The trigger is a plain HA time trigger reading `input_datetime`, so it fires in
Home Assistant's own timezone — `Europe/London` — not UTC. It follows BST and
GMT on its own; 08:50 is 08:50 on the bedroom clock all year.

It is **one-shot**. Arming is for the *next* wake-up only; the ring clears the
flag on its way out, so a morning you did not ask for is never rung. A press
while it is ringing dismisses it, and stays quiet — no confirmation at that
hour. To make it repeat daily, delete the `input_boolean.turn_off` at the end
of `script.bedroom_alarm_ring`.

A fresh `input_datetime` starts at **00:00** and cannot be given a default:
`initial:` would win over the restored value and reset the wake-up time on
every restart. So the ring automation reads 00:00 as *never configured* and
refuses to fire, and the card shows `Time not set`. On a from-scratch rebuild,
set the time once from the card.

The alarm itself is the QNAP handpan track faded in from 0.05 to 0.30 over 90s
and then held for up to 20 minutes. It is deliberately *not* wrapped in
`sonos.snapshot`/`restore` the way the spoken confirmation is: at wake-up time
the 12h pink noise from button 4 is often still playing, and restoring would
put the bedroom straight back to sleep. Only the speaker's prior volume is
captured and handed back.

If the NFS media mount has been orphaned by a NAS reboot — the failure mode
`sleep_sounds.yaml` documents, where `ha mounts info` still claims the mount is
active — the handpan cannot play, so the script falls back within 10s to
looping `/media/local/timer_ring.wav` off the Pi's own filesystem. A silent
alarm is the one outcome worth extra machinery to avoid. It tells the two cases
apart by the track URI Sonos reports rather than by whether the speaker is
playing, because the pink noise it is replacing also reads as `playing`.

The spoken confirmation plays at volume 0.12 — below the pink noise (0.18) it
often interrupts, since it arrives at the bedside with no fade. The wake-up
ramp is separate and climbs to 0.30.

Piper is given the time spelled out (`eight fifty A M`) rather than `8:50 am`:
espeak-ng's normaliser reads the latter as "eight fifty" plus the word *am*, as
in "I am". `script.bedroom_alarm_say` builds those words from the helper, so
callers pass only `set` or `turned off` and the phrasing lives in one place.

### Retired

Button 3's `Alarm Control` automation and the `800_alarm` / `830_alarm` helpers
were an earlier attempt at the same idea that never rang anything. The
automation is gone from `/config/automations.yaml`; the two helpers are
storage-mode UI helpers and are deleted from Settings → Devices & Services →
Helpers. Button 3 is now free.

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

## Cluster watchdog — `packages/nature-watchdog.yaml`

The third vantage point for cereal cluster monitoring. cereal's own Prometheus cannot
report that cereal is dead; Home Assistant runs on separate hardware, on the same LAN,
with phone push already working, so it is the one observer that survives the whole
cluster going away.

| Signal | Detects |
|---|---|
| ping `.50`–`.53` | individual nodes going away |
| all four `off` at once | the LAN/switch leg outage that recurred on 2026-07-15, -24 and -25 |
| TCP `10.30.1.50:6443` | the API server hung while the node still pings — the shape of the 2026-07-18 crackle outage |
| `nature-cluster-heartbeat` webhook | Alertmanager's always-firing `Watchdog` alert, POSTed every minute. **Its absence for 15 minutes is the dead-man's switch.** |
| `nature-critical-alert` webhook | Every `severity: critical` alert, relayed as a second delivery path so a broken Telegram token cannot swallow it silently |

Both webhooks are fed by receivers in `kubernetes/monitoring/helmrelease.yaml`. Never
silence the `Watchdog` alert in Alertmanager — doing so disables the dead-man's switch.

Deployed by `./deploy.sh` along with the other packages. Two things to do once:

1. Replace every `notify.mobile_app_REPLACE_ME` with your companion-app entity
   (Developer Tools → Actions → search "notify").
2. Prove the dead-man's switch actually fires rather than assuming it does:
   ```sh
   export KUBECONFIG=talos/kubeconfig
   kubectl -n monitoring scale sts/alertmanager-kube-prometheus-stack-alertmanager --replicas=0
   # wait ~16 minutes -> expect a critical phone push
   kubectl -n monitoring scale sts/alertmanager-kube-prometheus-stack-alertmanager --replicas=1
   ```

The `ping` binary_sensor YAML platform was removed from Home Assistant (it is config-flow
only now), which is why these are `command_line` sensors.
