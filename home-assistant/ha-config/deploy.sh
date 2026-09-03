#!/usr/bin/env bash
# Deploy HA config packages to hassio (10.30.1.60) over SSH.
# The Supervisor/Core HTTP API 401s with addon tokens (re-confirmed 2026-09-04:
# both http://supervisor/core/api/ and http://homeassistant:8123/api/ return
# 401), so scp + the `ha` CLI is the only reliable path and live entity state
# cannot be queried from here. That constraint shapes the verification below.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HASSIO_HOST="${HASSIO_HOST:-root@10.30.1.60}"

# ---------------------------------------------------------------------------
# 1. Validate filenames BEFORE anything leaves this machine.
# ---------------------------------------------------------------------------
# `packages: !include_dir_named packages` turns each FILENAME into the package
# NAME, and HA validates that as a slug. A hyphen makes HA log
#   "invalid slug nature-watchdog (try nature_watchdog). Package will not be
#    initialized"
# as a WARNING and skip the file, while `ha core check` still reports the config
# valid. nature-watchdog.yaml shipped that way and every entity in it silently
# did not exist — on the one package whose job is to notice the cluster dying.
#
# This check runs first and locally: a bad name never reaches hassio. It used to
# run *after* the scp, so the offending file landed and then stayed there.
echo "==> Validating package filenames"
shopt -s nullglob
pkgs=("${SCRIPT_DIR}"/packages/*.yaml)
if [[ ${#pkgs[@]} -eq 0 ]]; then
    echo "ERROR: no package files found in ${SCRIPT_DIR}/packages/" >&2
    exit 1
fi
bad=0
for f in "${pkgs[@]}"; do
    n="$(basename "$f" .yaml)"
    if [[ ! "$n" =~ ^[a-z0-9_]+$ ]]; then
        echo "ERROR: package filename '$n.yaml' is not a valid slug — use [a-z0-9_] only." >&2
        echo "       HA would log 'invalid slug $n (try ${n//-/_})' as a WARNING and skip it," >&2
        echo "       while 'ha core check' still reports the config valid." >&2
        bad=1
    fi
done
[[ "$bad" -eq 0 ]] || exit 1
echo "    ${#pkgs[@]} package file(s), all valid slugs"

# ---------------------------------------------------------------------------
# 2. Preconditions on the remote
# ---------------------------------------------------------------------------
if ! ssh "$HASSIO_HOST" "grep -q 'packages: !include_dir_named packages' /config/configuration.yaml"; then
    cat >&2 <<'EOF'
ERROR: /config/configuration.yaml on hassio does not include the packages dir.
One-time manual edit required — under the EXISTING `homeassistant:` key (do
not add a duplicate top-level key), add:

  homeassistant:
    packages: !include_dir_named packages

Then re-run this script.
EOF
    exit 1
fi

# ---------------------------------------------------------------------------
# 3. Copy, then remove anything stale
# ---------------------------------------------------------------------------
ssh "$HASSIO_HOST" 'mkdir -p /config/packages'
scp "${SCRIPT_DIR}"/packages/*.yaml "${HASSIO_HOST}:/config/packages/"

# scp never deletes. A renamed package (nature-watchdog.yaml -> nature_watchdog
# .yaml) otherwise leaves the old copy behind forever, where it keeps tripping
# the slug warning — or, for a rename that IS a valid slug, silently runs as a
# duplicate package alongside the new one.
echo "==> Removing stale packages not present in the repo"
expected="$(printf '%s\n' "${pkgs[@]##*/}")"
removed="$(ssh "$HASSIO_HOST" "EXPECTED='${expected}'; \
    for remote in /config/packages/*.yaml; do \
        [ -e \"\$remote\" ] || continue; \
        base=\"\$(basename \"\$remote\")\"; \
        if ! printf '%s\n' \"\$EXPECTED\" | grep -qxF \"\$base\"; then \
            rm -f \"\$remote\" && echo \"\$base\"; \
        fi; \
    done")"
if [[ -n "$removed" ]]; then
    echo "$removed" | sed 's/^/    removed /'
else
    echo "    none"
fi

# ---------------------------------------------------------------------------
# 4. Validate, restart, and verify it actually loaded
# ---------------------------------------------------------------------------
echo "==> Validating config"
ssh "$HASSIO_HOST" 'ha core check'

# Mark where the log is now, so the post-restart scan only reads NEW lines.
# `ha core restart` restarts Core, not the host, so the journald boot id is
# unchanged and `ha core logs -b` cannot isolate this run.
log_mark="$(ssh "$HASSIO_HOST" 'ha core logs -n 100000 2>/dev/null | wc -l' | tr -d ' ')"

echo "==> Restarting Home Assistant core"
ssh "$HASSIO_HOST" 'ha core restart'

echo "==> Waiting for Core to come back"
ready=0
for _ in $(seq 1 60); do
    if ssh -o ConnectTimeout=10 "$HASSIO_HOST" 'nc -z -w 3 homeassistant 8123' 2>/dev/null; then
        ready=1
        break
    fi
    sleep 5
done
if [[ "$ready" -ne 1 ]]; then
    echo "ERROR: Core did not start listening on 8123 within 5 minutes." >&2
    echo "       Check: ssh ${HASSIO_HOST} 'ha core logs -n 100'" >&2
    exit 1
fi
echo "    Core is up"

# `ha core check` exits 0 on warnings, and a skipped package is only a warning —
# which is exactly how the hyphenated filename got through. So ask HA what it
# actually complained about while loading, reading only lines produced since the
# mark above.
#
# Note on what this can and cannot prove: it is authoritative for the failure
# mode we care about, because HA names the package it refused to initialise. It
# cannot positively confirm every entity exists, because the Core API is not
# reachable from here (401, see the header). The filename check in step 1 is
# what makes that failure impossible in the first place; this catches anything
# else HA rejected.
echo "==> Checking what Core said while loading"
new_logs="$(ssh "$HASSIO_HOST" "total=\$(ha core logs -n 100000 2>/dev/null | wc -l | tr -d ' '); \
    if [ \"\$total\" -ge ${log_mark} ]; then \
        ha core logs -n 100000 2>/dev/null | tail -n +$((log_mark + 1)); \
    else \
        ha core logs -n 500 2>/dev/null; \
    fi" || true)"

problems="$(printf '%s\n' "$new_logs" \
    | grep -iE 'invalid slug|will not be initialized|Setup failed for|Invalid config for|Unable to prepare setup' || true)"

if [[ -n "$problems" ]]; then
    echo "ERROR: Home Assistant rejected part of the config on startup:" >&2
    printf '%s\n' "$problems" | sed 's/^/    /' >&2
    exit 1
fi
echo "    no package or setup errors reported"
echo "==> Done"
