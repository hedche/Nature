# Hardware Inventory — Nature Homelab

All hardware discovered from live nodes via `talosctl get disks -i`, `get linkstatuses -i`, `get cpustat -i`, and `get memorystats -i`.

## Talos Kubernetes Cluster

### cereal — Control Plane (10.30.1.50)

| Component | Detail |
|-----------|--------|
| **Chassis** | HP 250 G5 **Notebook** PC (InsydeH2O UEFI firmware) — a laptop, not a desktop; `/sys/class/dmi/id/product_name` |
| **CPU** | Intel (4 cores) |
| **RAM** | 8 GB (7,998 MB) |
| **Battery** | `BAT1` + `ACAD` under `/sys/class/power_supply` — the only cluster node with a battery |
| **NIC** | Realtek RTL8111/8168/8211/8411 GbE — `eno1` (also `enp1s0`), MAC `3c:52:82:bb:75:8a`, driver `r8169`, 1 Gbps |
| **Install Disk** | Samsung MZNLN256HMHQ 256 GB M.2 SATA SSD — `/dev/sdb`, wwid `naa.5002538d41d60108`, serial `S2Y2NX0J377953`, bus `/pci0000:00/0000:00:17.0/ata1/host1/target1:0:0/1:0:0:0` |
| **Optical** | HP DVDRW DU8AESH (SATA, ata2) |

**Known issue:** HP InsydeH2O UEFI does not automatically create an EFI NVRAM boot entry for the Samsung SSD after Talos install. Secure Boot must be disabled, and the boot entry may need to be added manually or via the BIOS "Select a UEFI file as trusted" option.

**Known issue — runs on battery if the charger is unplugged.** cereal is a laptop, so an
unplugged charger does not fail loudly: it keeps running for roughly five hours and then
dies silently. This happened on 2026-07-26 — cereal came up fine after the relocation,
ran ~5h, and dropped at 02:48 UTC, taking the whole cluster's DNS with it (both CoreDNS
replicas were on it). Check with:

```sh
talosctl -n 10.30.1.50 read /sys/class/power_supply/ACAD/online   # 1 = charger connected
talosctl -n 10.30.1.50 read /sys/class/power_supply/BAT1/status   # Charging / Discharging
talosctl -n 10.30.1.50 read /sys/class/power_supply/BAT1/capacity # percent
```

The battery is a de-facto UPS for the control plane, but only while it holds charge — and
a discharged battery reads as an ordinary total outage. Worth a Prometheus alert on
`ACAD/online == 0`.

---

### crackle — Worker (10.30.1.52)

| Component | Detail |
|-----------|--------|
| **Chassis** | Dell OptiPlex 7060, serial `DD2FZT2` |
| **CPU** | Intel i5-8500T (6C/6T @ 2.10GHz) |
| **RAM** | 16 GB (2× 8 GB DDR4 — Micron 8ATF1G64HZ-2G6D1 + SK Hynix HMA81GS6AFR8N-UH) |
| **NIC** | `eno1` (6c:2b:59:d2:b8:9b) |
| **Install Disk** | Micron 2200S NVMe 256 GB — `/dev/nvme0n1`, wwid `eui.000000000000000100a0752025d26ea0` |
| **Storage Disk** | KIOXIA EXCERIA S SATA 960 GB — `/dev/sda`, wwid `naa.58ce38e801936b06` |

**Known issue — does not power on again after an AC loss.** On 2026-09-02 a power
event took out crackle and `pve` (10.30.1.55) together; power returned, and neither
came back on its own, while snap, pop, qnap, hassio and the gateway all did. cereal
rode it out on mains — its `ACAD/online` never dropped from 1 and its battery stayed
at 100% through the whole window, so whatever tripped did not reach its socket.

Both machines needed a physical power button press. The fix is a BIOS setting —
on the OptiPlex 7060 it is *Power Management → AC Recovery → Power On* (Dell), and
the equivalent "Restore on AC Power Loss" on the `pve` host. Until that is set, every
power blip is a manual trip to the machines.

Distinguishing this from the NVMe DMA-fault wedge (`docs/nvme-dma-fault-monitoring.md`)
is easy and worth doing before you walk over there:

| | DMA-fault wedge | Power loss |
|---|---|---|
| ICMP | still answers | dead, ARP incomplete |
| Talos apid | still answers | dead |
| Kernel log before it went | `DMAR:` fault storm | nothing — all NPD conditions `False` |
| Remote reboot | accepted, silently ignored | nothing to accept |

---

### snap — Worker (10.30.1.51)

| Component | Detail |
|-----------|--------|
| **Chassis** | Dell OptiPlex 7060, serial `F32YZS2` |
| **CPU** | Intel i5-8500T (6C/6T @ 2.10GHz) |
| **RAM** | 16 GB (2× 8 GB DDR4 — Micron 8ATF1G64HZ-2G6E1 + 8ATF1G64HZ-2G6D1) |
| **NIC** | `eno2` (54:bf:64:97:dd:49) |
| **Install Disk** | Micron 2200S NVMe 256 GB — `/dev/nvme0n1`, wwid `eui.000000000000000100a075202702db5f` |
| **Storage Disk** | KIOXIA EXCERIA S SATA 960 GB — `/dev/sda`, wwid `naa.58ce38e801936a51` |

---

### pop — Worker (10.30.1.53)

| Component | Detail |
|-----------|--------|
| **Chassis** | Dell OptiPlex 7060, serial `DCRDZT2` |
| **CPU** | Intel i5-8500T (6C/6T @ 2.10GHz) |
| **RAM** | 16 GB (2× 8 GB DDR4 — Crucial KHYXPX-MIE) |
| **NIC** | `eno1` (6c:2b:59:d2:a4:80) |
| **Install Disk** | KIOXIA KXG60ZNV256G NVMe 256 GB — `/dev/nvme0n1`, wwid `eui.00000000000000018ce38e0300290b0b` |
| **Storage Disk** | KIOXIA EXCERIA S SATA 960 GB — `/dev/sda`, wwid `naa.58ce38e801936c18` |

---

## Other Infrastructure

### QNAP NAS (10.30.1.20)

Serves PXE boot, NFS storage, and Docker containers. See `pxe/README.md`.

### Raspberry Pi — Home Assistant

Runs Home Assistant OS. See `home-assistant/README.md`.

---

## Disk Selector Reference

Used in Talos machine configs to target the correct install disk per node.

| Node | Selector | Value |
|------|----------|-------|
| cereal | `wwid` | `naa.5002538d41d60108` |
| snap | `disk` | `/dev/nvme0n1` |
| crackle | `wwid` | `eui.000000000000000100a0752025d26ea0` |
| pop | `disk` | `/dev/nvme0n1` |
