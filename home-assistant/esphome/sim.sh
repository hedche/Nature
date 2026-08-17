#!/usr/bin/env bash
# Run the bedroom panel's real UI in a desktop SDL window (no hardware).
#
#   ./sim.sh                        compile + open the window; Ctrl-C to quit
#   ./sim.sh shot [out.png]         compile, capture one frame, exit
#   ./sim.sh compile                compile only
#
# Anything after the subcommand is passed straight to esphome, so scenarios
# need no file edits:
#
#   ./sim.sh shot pouring.png -s sim_weather pouring -s sim_rain_mm 12.4
#   ./sim.sh shot music.png    -s sim_page music_page
#   ./sim.sh shot              -s sim_page music_page   # defaults to sim-shot.png
#   ./sim.sh                   -s sim_media_title "A very long track name ..."
#
# See bedroom-panel-sim.yaml for the full list of sim_* substitutions.
#
# Needs SDL2 (brew install sdl2) and, for `shot`, Screen Recording permission
# for your terminal (System Settings > Privacy & Security > Screen Recording).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="bedroom-panel-sim.yaml"

command -v esphome >/dev/null 2>&1 || { echo "ERROR: esphome required (uv tool install esphome==2026.7.4)" >&2; exit 1; }
command -v sdl2-config >/dev/null 2>&1 || { echo "ERROR: SDL2 required (brew install sdl2)" >&2; exit 1; }

cd "$SCRIPT_DIR"

# Where the window lands, straight from the config so the two can't drift.
# Only the display block, so a stray `x:` in the touchscreen lambdas below it
# can't be mistaken for the window position.
geom() {
    awk -v k="$1:" '/^display:/{d=1} d && /^touchscreen:/{exit} d && $1==k {print $2; exit}' "$CONFIG"
}
WIN_X="$(geom x)"; WIN_Y="$(geom y)"
WIN_W="$(geom width)"; WIN_H="$(geom height)"
for v in "$WIN_X" "$WIN_Y" "$WIN_W" "$WIN_H"; do
    [[ "$v" =~ ^[0-9]+$ ]] || { echo "ERROR: could not read window geometry from $CONFIG (got '$v')" >&2; exit 1; }
done

# A leading option means no subcommand was given, so default to `run` rather
# than treating -s as one.
CMD=run
if [[ $# -gt 0 && "$1" != -* ]]; then CMD="$1"; shift; fi

case "$CMD" in
    compile|run)
        # esphome run builds and execs the binary itself; Ctrl-C stops both.
        exec esphome "$@" "$CMD" "$CONFIG"
        ;;
    shot)
        OUT="sim-shot.png"
        if [[ $# -gt 0 && "$1" != -* ]]; then OUT="$1"; shift; fi
        [[ "$OUT" = /* ]] || OUT="${SCRIPT_DIR}/${OUT}"
        ;;
    *)
        echo "usage: $0 [run|shot|compile] [out.png] [esphome args...]" >&2
        exit 2
        ;;
esac

# ---- shot: compile, run headless-ish, grab one frame, tear down ----

# esphome logs its INFO lines to stderr, so fold both streams together before
# picking the binary path out of them.
BIN="$(esphome "$@" compile "$CONFIG" 2>&1 | tee /dev/stderr \
        | sed -n "s/.*Successfully compiled program to path '\(.*\)'.*/\1/p" | tail -1)"
[[ -x "$BIN" ]] || { echo "ERROR: compile produced no runnable binary" >&2; exit 1; }

# The simulator's own log goes straight to this terminal: the host binary
# block-buffers stdout whenever it isn't a tty, so a redirected log file stays
# empty for the whole run and is useless both to read and to wait on.
"$BIN" &
PID=$!
# shellcheck disable=SC2064
trap "kill $PID 2>/dev/null || true" EXIT

# Readiness signal is the API port binding instead. Components set up in
# priority order and the API is late in that order, so once 6053 accepts, the
# display and LVGL are already up. (If you ever drop `api:` from the sim
# config, this check has to change.)
READY=0
for _ in $(seq 1 150); do
    if (exec 3<>/dev/tcp/127.0.0.1/6053) 2>/dev/null; then READY=1; break; fi
    kill -0 "$PID" 2>/dev/null || { echo "ERROR: simulator exited early (see its log above)" >&2; exit 1; }
    sleep 0.2
done
# Without this the capture would grab whatever is at those coordinates — the
# desktop, another window — and cheerfully report success.
[[ "$READY" = 1 ]] || { echo "ERROR: simulator never came up (30s) — see its log above" >&2; exit 1; }
# Let on_boot push the mock values in and LVGL finish its first draw.
sleep 2

screencapture -x -R"${WIN_X},${WIN_Y},${WIN_W},${WIN_H}" "$OUT" || {
    echo "ERROR: screencapture failed — grant your terminal Screen Recording permission" >&2
    exit 1
}

# Retina captures at 2x; normalise so screenshots are diffable against each other.
sips -z "$WIN_H" "$WIN_W" "$OUT" >/dev/null 2>&1 || true

echo "captured $OUT ($(sips -g pixelWidth -g pixelHeight "$OUT" 2>/dev/null | tr -d ' \n' | sed 's/.*pixelWidth:/w=/;s/pixelHeight:/ h=/'))"
