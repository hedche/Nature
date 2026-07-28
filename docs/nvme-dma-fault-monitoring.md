# NVMe DMA-fault monitoring — handoff

Context: `crackle` (10.30.1.52) went NotReady 2026-07-18 and stayed down until a physical
power-cycle on 2026-07-27. Root cause was an IOMMU DMAR fault storm from the NVMe
controller. Goal of this workflow: alert on the fault storm *before* it wedges the node.

## What to detect

Source: `talosctl -n <ip> dmesg` (kernel ring buffer).

Primary signal — DMAR faults from the NVMe PCI address:

```
DMAR: [DMA Read NO_PASID] Request device [01:00.0] fault addr 0x... [fault reason 0x06] PTE Read access is not set
```

Secondary signal — Talos block controller lock loop that follows:

```
failed to lock device, retrying later   # id: nvme0n1
```

Suggested match: `DMAR:.*fault` and `failed to lock device`.

## Thresholds

| state | observed |
|---|---|
| healthy | zero of either line |
| failing | ~250 DMAR faults/sec (`1313 callbacks suppressed` per 5s), lock loop ~10/sec |

There is no gradual ramp — it goes from zero to a storm. **Any sustained non-zero rate is
actionable.** Alert on >10 DMAR faults in 60s to allow for a one-off.

## Why node-level checks are not enough

During the storm the node looked partly alive, so these did **not** fire:

- ICMP — fine
- Talos apid :50000 — answered normally
- `talosctl services` — kubelet reported state `Running`
- Ceph — stayed 3/3 OSDs up; the osd-0 container kept running under containerd

What did break: kubelet healthz on `127.0.0.1:10248` (hangs), and therefore node Ready.

So pair the dmesg check with a **kubelet healthz probe**, not just a ping or apid check.

## Scope

Applies to any node with an NVMe system disk. Confirmed affected hardware:

- `crackle` — Micron 2200S NVMe 256GB, PCI `01:00.0`, serial `200225D26EA0`

Do not key the alert on `01:00.0` alone — other nodes will differ. Match `DMAR:.*fault`
and report the device ID from the matched line.

## Alert should say

Go straight to a **physical power-cycle**. In this state remote reboots are accepted and
then silently ignored — `talosctl reboot`, `talosctl reboot -e <ip>`, and
`talosctl reboot --mode powercycle` were all tried on 2026-07-24 and uptime kept climbing.
The graceful shutdown sequencer wedges on the same stuck NVMe.

If it recurs on the same drive: reseat or replace the Micron 2200S, or check for a
firmware update.

## Caveat

The 2026-07-27 boot was clean — no DMAR faults, no lock loop. This monitoring is for
recurrence; there is currently nothing to observe, so **generate a synthetic match to test
the alert path** rather than waiting for a real event.
