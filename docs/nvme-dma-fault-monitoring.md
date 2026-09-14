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
firmware update. **It has recurred — see below. Replacement is now due.**

## Caveat

The 2026-07-27 boot was clean — no DMAR faults, no lock loop. This monitoring is for
recurrence; there is currently nothing to observe, so **generate a synthetic match to test
the alert path** rather than waiting for a real event.

## Recurrence — 2026-09-14

Same drive, same fault line (`[01:00.0] ... fault reason 0x06`), after ~10 days of clean
uptime. Timeline (UTC):

| time | event |
|---|---|
| 06:48:15 | NPD sets `NVMeDMAFault=True` on crackle |
| 06:48:19 | `mon.d` crashes — its data is under `/var/lib/rook` on the NVMe `EPHEMERAL` partition; the pod then hangs in Terminating (container kill times out) |
| 06:57:47 | `CephMonQuorumAtRisk` (2/3 mons); later `KubePdbNotEnoughHealthyPods` (mon PDB) and `CephHealthWarning` |
| 08:19 | still storming: ~1283 callbacks suppressed per 5s, `nvme nvme0: Identify namespace failed (-5)` every 30s. Node still Ready, kubelet healthz OK, osd.0 up (it is on the SATA `sda`, not the NVMe) |
| ~12:25 | physical power-cycle; Ready 12:25:54, zero DMAR faults since boot; Rook replaced `mon-d` with `mon-e` |

Differences from July: the kubelet did **not** wedge (at least 90 min in), so the node never
went NotReady — the only pages were Ceph symptoms of the stuck mon.

**`NVMeDMAFaultStorm` did not fire.** It keyed on `problem_counter{reason="NVMeDMAFault"}`,
which comes from a `permanent` NPD rule. Permanent rules increment the counter only when the
condition changes, so it read `1` for the whole storm and `increase[5m] > 10` was
unreachable. The synthetic test above only ever checked the condition, so it never caught
this. Fix: a second, `temporary` rule on the same pattern (`NVMeDMAFaultEvent`) counts every
matching line, and the alert keys off that. The permanent condition is kept for the
out-of-band Grafana Cloud alert.

After the power-cycle, Ceph keeps `RECENT_CRASH` (and so `CephHealthWarning`) for two weeks
unless the crash is acknowledged with `ceph crash archive-all` from the toolbox.
