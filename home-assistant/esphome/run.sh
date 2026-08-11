#!/usr/bin/env bash
# Build/flash ESPHome devices from the Mac (never on the hassio Pi — it OOMs).
#
#   ./run.sh                     # compile + upload bedroom-panel.yaml
#   ./run.sh compile             # compile only
#   ./run.sh logs                # stream logs
#   ./run.sh run other.yaml      # another device
#
# Renders esphome/secrets.yaml (gitignored) from the out-of-repo secrets
# file so that !secret references resolve, then execs the esphome CLI.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${REPO_ROOT}/scripts/secrets-path.sh"

command -v yq >/dev/null 2>&1 || { echo "ERROR: yq required (brew install yq)" >&2; exit 1; }
command -v esphome >/dev/null 2>&1 || { echo "ERROR: esphome required (uv tool install esphome==2026.7.4)" >&2; exit 1; }
[[ -f "$SECRETS_FILE" ]] || { echo "ERROR: secrets file not found at $SECRETS_FILE" >&2; exit 1; }

if [[ "$(yq eval '.esphome' "$SECRETS_FILE")" == "null" ]]; then
    echo "ERROR: no 'esphome:' section in the secrets file — see talos/secrets.yaml.template" >&2
    exit 1
fi

# Render the ESPHome-native secrets file only for the duration of the
# command — ESPHome needs it adjacent to the device YAML to resolve
# !secret, but it should never linger in the working tree (gitignored
# regardless, belt and braces).
umask 077
yq eval '.esphome' "$SECRETS_FILE" > "${SCRIPT_DIR}/secrets.yaml"
trap 'rm -f "${SCRIPT_DIR}/secrets.yaml"' EXIT

cd "$SCRIPT_DIR"
esphome "${1:-run}" "${2:-bedroom-panel.yaml}" "${@:3}"
