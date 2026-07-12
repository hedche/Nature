#!/usr/bin/env bash
# hermes-io-error-watchdog — self-heal the hermes VM after a USB-disk dropout.
#
# The 1TB USB HDD passed through to hermes (vmid 157, scsi1) sits behind an aging
# ASMedia ASM1051 USB3-SATA bridge whose SuperSpeed link intermittently resets and
# disconnects (see proxmox/pve-host/README.md for the full RCA). When the device
# vanishes mid-I/O, QEMU pauses the guest in the `io-error` state: from the LAN this
# looks like "hermes is down" (ping/SSH/ports dead) even though pve itself is fine.
#
# This unit polls for that state and, once the disk has re-enumerated healthy,
# recovers with stop->start (NOT `qm resume`, which reuses the stale device handle).
# It is a safety net, not the fix — the fix is on the physical USB link.
set -euo pipefail

VMID=157
TAG=hermes-watchdog

status=$(qm status "$VMID" 2>/dev/null | awk '{print $2}') || exit 0
[ "$status" = "io-error" ] || exit 0

# Resolve the passthrough disk from the VM config (scsi1) so this isn't hardcoded.
disk=$(qm config "$VMID" 2>/dev/null | sed -n 's/^scsi1: \([^,]*\).*/\1/p')

logger -t "$TAG" "VM $VMID is in io-error; disk=$disk — checking the disk is back before recovering"

# Only recover once the disk is actually present and readable again; otherwise the
# restart would just re-freeze. Retry on the next timer tick if it's not ready yet.
if [ -z "$disk" ] || [ ! -e "$disk" ]; then
    logger -t "$TAG" "passthrough disk $disk not present yet; deferring to next tick"
    exit 0
fi
if ! dd if="$disk" of=/dev/null bs=1M count=1 iflag=direct >/dev/null 2>&1; then
    logger -t "$TAG" "disk $disk present but not readable yet; deferring to next tick"
    exit 0
fi

logger -t "$TAG" "disk healthy; stop->start VM $VMID to reopen the device handle"
qm stop "$VMID" >/dev/null 2>&1 || true
sleep 5
qm start "$VMID" >/dev/null 2>&1
logger -t "$TAG" "VM $VMID recovery issued (start returned $?)"
