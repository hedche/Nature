#!/usr/bin/env bash
# Install host-level config onto the Proxmox node `pve` (10.30.1.55).
#
# Unlike the VMs in ../ (Terraform-provisioned), these are OS-level bits that live
# on the pve host itself: currently the hermes io-error watchdog (see README.md).
# Idempotent — safe to re-run. Run from the repo on your Mac:
#
#     ./proxmox/pve-host/install.sh            # add --dry-run to preview
#
set -euo pipefail

PVE_HOST="${PVE_HOST:-pve}"          # ssh alias or user@10.30.1.55
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRY_RUN=""
[ "${1:-}" = "--dry-run" ] && DRY_RUN="echo [dry-run]"

echo ">> Installing pve-host config onto ${PVE_HOST}"

# Ship the watchdog script + systemd units to a staging dir, then move into place
# as root. rsync keeps this cheap and idempotent.
$DRY_RUN rsync -a --delete \
    "${SELF_DIR}/hermes-io-error-watchdog.sh" \
    "${SELF_DIR}/systemd/" \
    "${PVE_HOST}:/tmp/pve-host-stage/"

$DRY_RUN ssh "${PVE_HOST}" 'bash -euo pipefail -s' <<'REMOTE'
install -m 0755 /tmp/pve-host-stage/hermes-io-error-watchdog.sh \
    /usr/local/bin/hermes-io-error-watchdog.sh
install -m 0644 /tmp/pve-host-stage/hermes-io-error-watchdog.service \
    /etc/systemd/system/hermes-io-error-watchdog.service
install -m 0644 /tmp/pve-host-stage/hermes-io-error-watchdog.timer \
    /etc/systemd/system/hermes-io-error-watchdog.timer
rm -rf /tmp/pve-host-stage
systemctl daemon-reload
systemctl enable --now hermes-io-error-watchdog.timer
echo "watchdog timer:"; systemctl --no-pager list-timers hermes-io-error-watchdog.timer | head -3
REMOTE

echo ">> Done. Watch it act with:  ssh ${PVE_HOST} 'journalctl -t hermes-watchdog -f'"
