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
#   ./sim.sh shot alarm.png    -s sim_page alarm_page
#   ./sim.sh shot              -s sim_page music_page   # defaults to sim-shot.png
#   ./sim.sh                   -s sim_media_title "A very long track name ..."
#
# See bedroom-panel-sim.yaml for the full list of sim_* substitutions.
#
# `shot` never touches the desktop: the simulator is compiled with the
# `sim_shot` substitution set, renders headlessly (SDL dummy video driver),
# dumps its own backbuffer to a BMP once the mock values are drawn, and
# exits. No window, no Screen Recording permission, and the PNG is the
# framebuffer pixel for pixel.
#
# Needs SDL2 (brew install sdl2).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="bedroom-panel-sim.yaml"

command -v esphome >/dev/null 2>&1 || { echo "ERROR: esphome required (uv tool install esphome==2026.7.4)" >&2; exit 1; }
command -v sdl2-config >/dev/null 2>&1 || { echo "ERROR: SDL2 required (brew install sdl2)" >&2; exit 1; }

cd "$SCRIPT_DIR"

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

# ---- shot: compile with the dump path baked in, run, convert ----

# The dump is BMP (SDL writes that natively); sips turns it into the PNG the
# caller asked for. Same directory as the target so a full disk fails loudly
# at the same place either way.
BMP="${OUT%.png}.bmp"
rm -f "$BMP"
# Never leave the intermediate behind, however this exits.
trap 'rm -f "$BMP"' EXIT

# esphome logs its INFO lines to stderr, so fold both streams together before
# picking the binary path out of them.
BIN="$(esphome -s sim_shot "$BMP" "$@" compile "$CONFIG" 2>&1 | tee /dev/stderr \
        | sed -n "s/.*Successfully compiled program to path '\(.*\)'.*/\1/p" | tail -1)"
[[ -x "$BIN" ]] || { echo "ERROR: compile produced no runnable binary" >&2; exit 1; }

# The binary exits by itself once the frame is written (exit 3 if the dump
# failed). Cap it so a simulator that never reaches on_boot can't hang a CI
# run; its own log goes straight to this terminal. SDL's dummy video driver
# renders into memory only — no window flashes up, no WindowServer needed,
# and the frame is byte-identical to the on-screen one.
SDL_VIDEODRIVER=dummy "$BIN" &
PID=$!
# shellcheck disable=SC2064
trap "kill $PID 2>/dev/null || true; rm -f '$BMP'" EXIT
for _ in $(seq 1 300); do
    kill -0 "$PID" 2>/dev/null || break
    sleep 0.1
done
if kill -0 "$PID" 2>/dev/null; then
    echo "ERROR: simulator still running after 30s without writing a frame — see its log above" >&2
    exit 1
fi
wait "$PID" || { echo "ERROR: simulator exited without a frame (see its log above)" >&2; exit 1; }
[[ -s "$BMP" ]] || { echo "ERROR: simulator exited but wrote no frame to $BMP" >&2; exit 1; }

sips -s format png "$BMP" --out "$OUT" >/dev/null || { echo "ERROR: could not convert $BMP to PNG" >&2; exit 1; }

echo "captured $OUT ($(sips -g pixelWidth -g pixelHeight "$OUT" 2>/dev/null | tr -d ' \n' | sed 's/.*pixelWidth:/w=/;s/pixelHeight:/ h=/'))"
