# Hardware Inventory — Nature Homelab

All hardware discovered from live nodes via `talosctl get disks -i`, `get linkstatuses -i`, `get cpustat -i`, and `get memorystats -i`.

## Talos Kubernetes Cluster

### cereal — Control Plane (10.30.1.50)

| Component | Detail |
|-----------|--------|
| **Chassis** | HP EliteDesk (InsydeH2O UEFI firmware) |
| **CPU** | Intel (4 cores) |
| **RAM** | 8 GB (7,998 MB) |
| **NIC** | Realtek RTL8111/8168/8211/8411 GbE — `eno1` (also `enp1s0`), MAC `3c:52:82:bb:75:8a`, driver `r8169`, 1 Gbps |
| **Install Disk** | Samsung MZNLN256HMHQ 256 GB M.2 SATA SSD — `/dev/sdb`, wwid `naa.5002538d41d60108`, serial `S2Y2NX0J377953`, bus `/pci0000:00/0000:00:17.0/ata1/host1/target1:0:0/1:0:0:0` |
| **Optical** | HP DVDRW DU8AESH (SATA, ata2) |

**Known issue:** HP InsydeH2O UEFI does not automatically create an EFI NVRAM boot entry for the Samsung SSD after Talos install. Secure Boot must be disabled, and the boot entry may need to be added manually or via the BIOS "Select a UEFI file as trusted" option.

---

### crackle — Worker (10.30.1.52)

| Component | Detail |
|-----------|--------|
| **Chassis** | HP EliteDesk (same model as snap/pop) |
| **CPU** | TBD — same hardware class as snap/pop |
| **RAM** | TBD |
| **NIC** | TBD — `eno1` |
| **Install Disk** | Micron 2200S NVMe 256 GB — wwid `eui.000000000000000100a0752025d26ea0` |
| **Storage Disk** | KIOXIA EXCERIA SATA SSD 960 GB — left raw for future HA storage pool |

---

### snap — Worker (10.30.1.51)

| Component | Detail |
|-----------|--------|
| **Chassis** | HP EliteDesk (same model as crackle/pop) |
| **CPU** | TBD |
| **RAM** | TBD |
| **NIC** | TBD — `eno1` |
| **Install Disk** | NVMe — wwid TBD (node not yet discovered) |
| **Storage Disk** | SATA SSD — TBD |

---

### pop — Worker (10.30.1.53)

| Component | Detail |
|-----------|--------|
| **Chassis** | HP EliteDesk (same model as crackle/snap) |
| **CPU** | TBD |
| **RAM** | TBD |
| **NIC** | TBD — `eno1` |
| **Install Disk** | NVMe — wwid TBD (node not yet discovered) |
| **Storage Disk** | SATA SSD — TBD |

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
| crackle | `wwid` | `eui.000000000000000100a0752025d26ea0` |
| snap | `wwid` | TBD |
| pop | `wwid` | TBD |
