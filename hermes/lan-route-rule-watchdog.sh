#!/usr/bin/env bash
# lan-route-rule-watchdog — keep hermes reachable on its own LAN.
#
# hermes runs a manually-installed Tailscale with accept-routes on, and the cereal
# subnet router advertises 10.30.1.0/24 — hermes's OWN subnet. Tailscale therefore
# puts `10.30.1.0/24 dev tailscale0` in routing table 52, which is consulted at rule
# priority 5270, ahead of main (32766). Without an exemption, every reply to a LAN
# peer is steered into tailscale0 and blackholed: from the LAN hermes goes dark
# (ping, SSH, :8080 all dead) while the VM itself is perfectly healthy.
#
# The exemption is one rule at priority 100 sending LAN->LAN traffic to the main
# table. tailscaled.service adds it in ExecStartPost, but that fires only at service
# start, and tailscaled reprograms routing whenever peers churn. On 2026-07-25 the
# rule was flushed out from under a tailscaled that had been up 14 days (NRestarts=0),
# taking qBittorrent off the LAN with no restart to reinstate it. This unit re-asserts
# the rule so a flush costs one timer tick instead of an outage.
set -euo pipefail

LAN_CIDR="${LAN_CIDR:-10.30.1.0/24}"
PRIORITY="${PRIORITY:-100}"
TAG=hermes-lan-route-rule

# Match on the live rule set rather than `ip rule show priority N`, so a rule left
# at the right priority but the wrong selectors still counts as missing.
if ip rule show 2>/dev/null | grep -qE "^${PRIORITY}:[[:space:]]+from ${LAN_CIDR} to ${LAN_CIDR} lookup main"; then
    exit 0
fi

# Clear any stale occupant of the priority before claiming it, so repeated repairs
# can't stack duplicate rules.
ip rule del priority "$PRIORITY" 2>/dev/null || true
ip rule add from "$LAN_CIDR" to "$LAN_CIDR" lookup main priority "$PRIORITY"

logger -t "$TAG" "re-added the missing LAN exemption rule (pref ${PRIORITY}, ${LAN_CIDR} -> main); LAN reachability had been broken"
