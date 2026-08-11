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

echo "==> Validating config"
ssh "$HASSIO_HOST" 'ha core check'
echo "==> Restarting Home Assistant core"
ssh "$HASSIO_HOST" 'ha core restart'
echo "==> Done"
