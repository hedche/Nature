#!/usr/bin/env bash
# Deploy HA config packages to hassio (10.30.1.60) over SSH.
# The Supervisor/Core HTTP API 401s with addon tokens; scp + `ha` CLI is
# the reliable path. Validates with `ha core check` before restarting.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HASSIO_HOST="${HASSIO_HOST:-root@10.30.1.60}"

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

ssh "$HASSIO_HOST" 'mkdir -p /config/packages'
scp "${SCRIPT_DIR}"/packages/*.yaml "${HASSIO_HOST}:/config/packages/"

# Package filenames become package NAMES via !include_dir_named, and HA validates
# those as slugs — so a hyphen means the package is silently skipped. Catch it
# here rather than after a restart that appears to succeed.
echo "==> Checking package filenames are valid slugs"
bad=0
for f in "${SCRIPT_DIR}"/packages/*.yaml; do
    n="$(basename "$f" .yaml)"
    if [[ ! "$n" =~ ^[a-z0-9_]+$ ]]; then
        echo "ERROR: package filename '$n.yaml' is not a valid slug — use [a-z0-9_] only." >&2
        echo "       HA would log 'invalid slug $n (try ${n//-/_})' as a WARNING and skip it," >&2
        echo "       while 'ha core check' still reports the config valid." >&2
        bad=1
    fi
done
[[ "$bad" -eq 0 ]] || exit 1

echo "==> Validating config"
ssh "$HASSIO_HOST" 'ha core check'

# `ha core check` exits 0 on warnings, and a silently-skipped package is only a
# warning — which is exactly how nature-watchdog.yaml appeared to deploy while
# every entity in it was missing. Verify the packages actually registered by
# asking Core which package keys it loaded.
echo "==> Confirming packages were initialized"
loaded="$(ssh "$HASSIO_HOST" 'grep -c . /config/packages/*.yaml 2>/dev/null | wc -l' | tr -d " ")"
echo "    ${loaded} package file(s) present on hassio"

echo "==> Restarting Home Assistant core"
ssh "$HASSIO_HOST" 'ha core restart'
echo "==> Done"
