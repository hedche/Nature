# Tailscale Subnet Router — Remote Access to the Cereal Cluster

The simplest way to reach the `10.30.1.0/24` network (and therefore the Talos Kubernetes cluster) from a remote machine is to run a **Tailscale subnet router** on a device that lives inside that subnet.

Once the subnet router is advertising the route and your remote client is accepting it, `kubectl`, `talosctl`, and any other cluster tools work exactly as if you were on the local network.

---

## Prerequisites

- A device inside the `10.30.1.0/24` subnet running Linux/macOS/Windows with [Tailscale installed](https://tailscale.com/download). Good candidates from the Nature network:
  - `photon` (`10.30.1.90`) — Raspberry Pi 3A+ (CUPS server)
  - `hassio` (`10.30.1.60`) — Raspberry Pi 4B (Home Assistant)
  - `qnap` (`10.30.1.20`) — QNAP NAS
- A remote client machine (your laptop/workstation) with Tailscale installed.
- Both devices logged in to the **same tailnet**.

---

## 1. Configure the Subnet Router (LAN-side device)

SSH into a machine on the `10.30.1.0/24` subnet and run:

```bash
# Install Tailscale if not already present
curl -fsSL https://tailscale.com/install.sh | sh

# Bring Tailscale up and advertise the cluster subnet
sudo tailscale up --advertise-routes=10.30.1.0/24 --accept-dns=false
```

You will see a login URL. Open it in a browser, authenticate, and approve the machine.

### Enable the route in the Tailscale admin console

1. Go to [Tailscale Admin Console -> Machines](https://login.tailscale.com/admin/machines).
2. Find the subnet router machine and click the **...** menu.
3. Under **Edit route settings**, toggle **10.30.1.0/24** to **Enabled**.
4. Optionally disable key expiry for this machine (so it never falls off the tailnet).

---

## 2. Configure the Remote Client

On your laptop/workstation, run:

```bash
# Install Tailscale if not already present
curl -fsSL https://tailscale.com/install.sh | sh

# Connect and accept subnet routes
sudo tailscale up --accept-routes
```

Authenticate when prompted.

### Verify the route is active

```bash
tailscale status
```

You should see the subnet router machine with `10.30.1.0/24` listed next to it.

Check your routing table:

```bash
# macOS
netstat -rn | grep 10.30.1

# Linux
ip route | grep 10.30.1
```

You should see `10.30.1.0/24 via tailscale0` (or similar).

---

## 3. Client Environment Configuration

Create `talos/.env` on the client machine. This file should be **gitignored** — never commit it.

```bash
# === Network ===
# The cluster's local subnet (advertised by the subnet router)
CEREAL_SUBNET=10.30.1.0/24

# === Cluster endpoints ===
# Kubernetes API server (local IP, reachable once Tailscale routes are active)
CEREAL_ENDPOINT=https://10.30.1.50:6443

# Talos API endpoints (all nodes)
CEREAL_CONTROLPLANE=10.30.1.50
CEREAL_SNAP=10.30.1.51
CEREAL_CRACKLE=10.30.1.52
CEREAL_POP=10.30.1.53

# === Paths ===
# Absolute or repo-relative paths to the generated configs
KUBECONFIG="${PWD}/talos/kubeconfig"
TALOSCONFIG="${PWD}/talos/talosconfig"
```

### Load the environment

**Option A: Source manually (bash/zsh)**

```bash
cd /path/to/Nature
set -a && source talos/.env && set +a
```

**Option B: Use direnv (recommended)**

Add this to the existing `talos/.envrc`:

```bash
# --- Tailscale client env ---
# Only load if .env exists (kept untracked for per-machine differences)
if [[ -f "${PWD}/.env" ]]; then
    source "${PWD}/.env"
fi
```

Then run:

```bash
cd talos/
direnv allow
```

---

## 4. Verification Commands

With Tailscale connected and `.env` loaded, test from the client machine:

### Test subnet reachability

```bash
# Ping the control plane
ping -c 3 10.30.1.50

# Ping a worker
ping -c 3 10.30.1.51
```

### Test talosctl

```bash
# Assuming TALOSCONFIG is exported
talosctl version --nodes 10.30.1.50
talosctl dmesg --nodes 10.30.1.51
```

### Test kubectl

```bash
# Assuming KUBECONFIG is exported
kubectl get nodes -o wide
kubectl -n kube-system get pods
```

---

## 5. Quick Reference — One-liners

Copy-paste these into a shell after setting up the subnet router:

```bash
# --- On the LAN subnet router (run once) ---
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up --advertise-routes=10.30.1.0/24 --accept-dns=false

# --- On the remote client (run once) ---
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up --accept-routes

# --- Daily workflow on the client ---
tailscale status                # Confirm connected and routes active
source talos/.env               # Or let direnv handle it
talosctl version --nodes 10.30.1.50
kubectl get nodes
```

---

## Notes

- **No changes are needed on the Talos nodes themselves.** They remain on the local network; the subnet router bridges that network into your tailnet.
- **No Kubernetes or Talos reconfiguration is required.** The existing `talosconfig` and `kubeconfig` (which point to `10.30.1.50`) continue to work once the route is active.
- **Security:** Only devices you approve in the Tailscale ACL can reach `10.30.1.0/24`. By default, only your own tailnet devices can see the route.
- **High availability:** If the subnet router goes down, you lose access. For resilience, consider running subnet routers on two separate LAN machines (Tailscale supports active-active subnet routers).
