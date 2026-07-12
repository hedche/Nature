# pve host-level config

Terraform in [`../`](../README.md) provisions the **VMs** on the Proxmox node
`pve` (`10.30.1.55`). This directory holds OS-level config for the **host
itself** — things that can't be expressed as a VM resource. Apply with:

```sh
./proxmox/pve-host/install.sh          # from your Mac; --dry-run to preview
```

Idempotent; ships files over SSH (alias `pve`) and enables the systemd units.

## hermes USB-disk io-error watchdog

`hermes-io-error-watchdog.{sh,service,timer}` — a 60s timer that detects the
hermes VM (vmid 157) stuck in QEMU's `io-error` state and self-heals it with
`qm stop` → `qm start` (never `qm resume`, which reuses the stale device
handle). It verifies the passthrough disk has re-enumerated and is readable
before restarting, so it won't fight an in-progress dropout. Watch it:

```sh
ssh pve 'journalctl -t hermes-watchdog -f'
```

This is a **safety net, not the fix.** The fix is on the USB link — see below.

## RCA: why the 1TB USB HDD keeps dropping off the bus

**Symptom.** Every so often hermes goes unreachable from the LAN (ping / SSH /
qBittorrent / Plex / NFS all dead) while pve itself, the gateway, and the pve
API (`:8006`) stay up. `qm status 157` shows `io-error`: QEMU has *paused* the
guest because its `scsi1` backing device threw an I/O error mid-write. It is
not a crash and not a network outage.

**Evidence (2026-07-11).**

- The disk (`scsi1` = `/dev/disk/by-id/ata-ST1000LM024_HN-M101MBB_S318J9CF105631`)
  is a 2.5″ 5400rpm Samsung/Seagate M8 in a **bus-powered** Transcend StoreJet,
  behind an **ASMedia ASM1051** USB3-SATA bridge (`174c:5106`, `bcdUSB 3.00`,
  linking at `5000M` SuperSpeed).
- `dmesg` shows a repeating pattern: `usb 2-4: reset SuperSpeed USB device`
  events (Jul 9 13:25, Jul 11 13:18 & 19:03) that occasionally escalate to a
  hard `usb 2-4: USB disconnect` + `Synchronize Cache failed: DID_NO_CONNECT`
  — the device vanishes from the bus and immediately re-enumerates as a *new*
  device number (`sdb`→`sda`), orphaning QEMU's open fd.
- **The drive and its internal SATA link are healthy** — SMART `PASSED`,
  `UDMA_CRC_Error_Count = 0` (the definitive test for a bad data connection —
  clean), `Reallocated/Pending/Uncorrectable = 0`, no logged errors, 36 °C.
- **Software causes are ruled out**: the enclosure presents Bulk-Only
  Transport (`usb-storage`), *not* the reset-prone UAS path; USB autosuspend is
  already `control=on` (disabled) for the device.

**Root cause.** The failure is purely on the **USB-3 host↔enclosure physical
link**: an aging ASM1051 bridge with a captive cable on a bus-powered 2.5″
enclosure, whose marginal SuperSpeed PHY / power delivery drops the link. It is
**not** the drive, the SATA link, or software.

> Aside — longevity: SMART `Load_Cycle_Count = 305552`. This drive parks its
> heads very aggressively (~50% of rated load/unload life). Not the cause of the
> dropouts, but this disk will eventually wear out; keep backups of anything on
> `/mnt/data` you can't re-download.

### Durable fixes (in order of leverage)

The real cure is on the physical link. Options, cheapest first:

1. **Force USB 2.0 (High-Speed).** Take the flaky SuperSpeed PHY out of the loop
   entirely — plug the enclosure into a USB-2 port, or insert a USB-2 A-to-A
   cable, or disable xHCI/SuperSpeed for that port in the pve BIOS. Throughput
   caps at ~40 MB/s, which is irrelevant for a 5400rpm media drive served over
   1GbE NFS. **Most reliable, no cost.**
2. **Software adjunct — disable USB3 LPM for this bridge (APPLIED).** Targets
   the `reset SuperSpeed` events (low-power U1/U2 link-state transitions the
   ASM1051 mishandles). Added to `GRUB_CMDLINE_LINUX_DEFAULT` in
   `/etc/default/grub` on pve:

   ```
   usbcore.quirks=174c:5106:k        # k = USB_QUIRK_NO_LPM on kernel 6.17
   ```

   > The quirk-flag letters are **kernel-version-specific** and map
   > sequentially to the bit positions in `include/linux/usb/quirks.h`
   > (verified empirically here: `c`→`0x4`, `i`→`0x100`, so NO_LPM = BIT 10 =
   > `k` → `0x400`). Do **not** trust a letter from memory or an old wiki —
   > confirm after boot that the device's applied bitmask is `0x400`:
   > `cat /sys/bus/usb/devices/<node>/quirks` (find `<node>` via the `174c`
   > idVendor). When LPM is off, the `power/usb3_hardware_lpm_u1/u2` sysfs
   > attributes disappear.

   Applied via `update-grub` + reboot (hermes is the only VM — ~2 min outage).
   Reversible: remove the token, `update-grub`, reboot.
3. **Replace the enclosure/drive.** A modern UASP enclosure + a short certified
   cable, or a powered dock, or move off USB to a directly-attached SATA disk.
   Best long-term, but this NUC-class node has only NVMe internally, so external
   is the realistic path.

Whichever is chosen, the watchdog above stays as defense-in-depth.
