#!/usr/bin/env bash
# Idempotently deploy the Nature media stack (Gluetun + qBittorrent) to the hermes VM.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SECRETS_FILE="${REPO_ROOT}/secrets.yaml"

HERMES_SSH_HOST="${HERMES_SSH_HOST:-ubuntu@10.30.1.57}"
HERMES_DIR="${HERMES_DIR:-/home/ubuntu/nature-hermes}"
COMPOSE_PROJECT="${COMPOSE_PROJECT:-nature-hermes-media}"

DRY_RUN=false
SKIP_BOOTSTRAP=false

usage() {
    cat <<EOF
Usage: $0 [options]

Options:
  --host <ssh-host>       SSH target for hermes (default: ${HERMES_SSH_HOST})
  --remote-dir <path>     Remote managed directory (default: ${HERMES_DIR})
  --project <name>        Compose project name (default: ${COMPOSE_PROJECT})
  --skip-bootstrap        Skip the idempotent Docker install check.
  --dry-run               Show rsync changes without modifying hermes.
  -h, --help              Show this help.

Environment:
  HERMES_SSH_HOST, HERMES_DIR, COMPOSE_PROJECT
  NORDVPN_WIREGUARD_PRIVATE_KEY   overrides the key from ../secrets.yaml
  NORDVPN_SERVER_COUNTRIES        gluetun server filter (default: Netherlands)
EOF
}

require_command() {
    if ! command -v "$1" &>/dev/null; then
        echo "ERROR: $1 is required but not installed." >&2
        exit 1
    fi
}

validate_remote_path() {
    case "${HERMES_DIR}" in
        */nature-hermes) ;;
        *)
            echo "ERROR: refusing to rsync --delete to a path that does not end with nature-hermes: ${HERMES_DIR}" >&2
            exit 1
            ;;
    esac
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --host)
            HERMES_SSH_HOST="$2"
            shift 2
            ;;
        --remote-dir)
            HERMES_DIR="$2"
            shift 2
            ;;
        --project)
            COMPOSE_PROJECT="$2"
            shift 2
            ;;
        --skip-bootstrap)
            SKIP_BOOTSTRAP=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "ERROR: unknown argument: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

require_command rsync
require_command ssh
require_command yq

validate_remote_path

# --- Resolve the NordVPN WireGuard key (env var wins, else secrets.yaml) ---
WG_KEY="${NORDVPN_WIREGUARD_PRIVATE_KEY:-}"
if [[ -z "${WG_KEY}" && -f "${SECRETS_FILE}" ]]; then
    WG_KEY="$(yq -r '.nordvpn.wireguard_private_key // ""' "${SECRETS_FILE}")"
fi
if [[ -z "${WG_KEY}" || "${WG_KEY}" == "null" || "${WG_KEY}" == YOUR_* ]]; then
    cat >&2 <<EOF
ERROR: NordVPN WireGuard private key not found.
Add a nordvpn: stanza to ${SECRETS_FILE} (see talos/secrets.yaml.template),
or export NORDVPN_WIREGUARD_PRIVATE_KEY. Get the key from:
  https://my.nordaccount.com/dashboard/nordvpn/manual-configuration/
EOF
    exit 1
fi

SERVER_COUNTRIES="${NORDVPN_SERVER_COUNTRIES:-Netherlands}"

if [[ "${DRY_RUN}" == true ]]; then
    rsync_mode=(--dry-run --itemize-changes)
else
    rsync_mode=()

    # --- Idempotent Docker bootstrap (official apt repo) ---
    if [[ "${SKIP_BOOTSTRAP}" != true ]]; then
        ssh "${HERMES_SSH_HOST}" 'bash -s' <<'BOOTSTRAP'
set -eu
if command -v docker >/dev/null 2>&1; then
    exit 0
fi
echo "Docker not found — installing from the official apt repo..."
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    docker-ce docker-ce-cli containerd.io docker-compose-plugin
sudo usermod -aG docker "$USER"
echo "Docker installed."
BOOTSTRAP
    fi

    # --- Host preflight: data disk present, directories, managed marker ---
    ssh "${HERMES_SSH_HOST}" "
        set -eu
        if ! mountpoint -q /mnt/data; then
            echo 'ERROR: /mnt/data is not mounted (USB data disk absent?). Aborting.' >&2
            exit 1
        fi
        mkdir -p /mnt/data/torrents/tv /mnt/data/torrents/movies /mnt/data/torrents/incomplete
        mkdir -p /mnt/data/media/tv /mnt/data/media/movies
        mkdir -p /home/ubuntu/appdata/gluetun /home/ubuntu/appdata/qbittorrent /home/ubuntu/appdata/plex
        mkdir -p '${HERMES_DIR}'
        touch '${HERMES_DIR}/.nature-hermes-managed'
    "
fi

rsync -az --delete \
    --filter='P .nature-hermes-managed' \
    --filter='P .env' \
    --exclude='.envrc' \
    --exclude='.direnv/' \
    "${rsync_mode[@]}" \
    "${SCRIPT_DIR}/" "${HERMES_SSH_HOST}:${HERMES_DIR}/"

if [[ "${DRY_RUN}" == true ]]; then
    echo "Dry run complete. No changes were pushed to ${HERMES_SSH_HOST}:${HERMES_DIR}."
    exit 0
fi

# --- Write the secret .env on hermes (0600); never stored locally or in git ---
# PLEX_CLAIM is a short-lived (~4 min) one-time token from https://plex.tv/claim;
# forward it only when set so a fresh Plex config binds to the user's account.
{
    printf 'NORDVPN_WIREGUARD_PRIVATE_KEY=%s\nNORDVPN_SERVER_COUNTRIES=%s\n' \
        "${WG_KEY}" "${SERVER_COUNTRIES}"
    if [[ -n "${PLEX_CLAIM:-}" ]]; then
        printf 'PLEX_CLAIM=%s\n' "${PLEX_CLAIM}"
    fi
} | ssh "${HERMES_SSH_HOST}" "install -m 600 /dev/stdin '${HERMES_DIR}/.env'"

# --- Bring the stack up ---
ssh "${HERMES_SSH_HOST}" "
    set -eu
    cd '${HERMES_DIR}'
    test -f .nature-hermes-managed
    docker compose -p '${COMPOSE_PROJECT}' config >/dev/null
    docker compose -p '${COMPOSE_PROJECT}' up -d --remove-orphans
    docker compose -p '${COMPOSE_PROJECT}' ps
"

# --- Install the LAN->localhost proxy units (see systemd/ + README) ---
# Must run after compose up: an older stack may have held 0.0.0.0:8080, which
# the socket's 10.30.1.57:8080 bind collides with until Docker rebinds to
# 127.0.0.1 only. gluetun-httpproxy (:8888) serves Prowlarr's VPN indexer
# proxy the same way.
ssh "${HERMES_SSH_HOST}" "
    set -eu
    sudo install -m 644 '${HERMES_DIR}/systemd/qbittorrent-proxy.socket' /etc/systemd/system/
    sudo install -m 644 '${HERMES_DIR}/systemd/qbittorrent-proxy.service' /etc/systemd/system/
    sudo install -m 644 '${HERMES_DIR}/systemd/gluetun-httpproxy.socket' /etc/systemd/system/
    sudo install -m 644 '${HERMES_DIR}/systemd/gluetun-httpproxy.service' /etc/systemd/system/
    sudo systemctl daemon-reload
    sudo systemctl enable qbittorrent-proxy.socket gluetun-httpproxy.socket >/dev/null 2>&1
    sudo systemctl restart qbittorrent-proxy.socket gluetun-httpproxy.socket
"

# --- NFS export of /mnt/data for the cereal *arr stack (see README) ---
# The preflight above already guarantees /mnt/data is mounted; the systemd
# drop-in keeps nfs-server from ever exporting the empty stub dir on a boot
# where the USB disk is absent.
ssh "${HERMES_SSH_HOST}" "
    set -eu
    if ! dpkg -s nfs-kernel-server >/dev/null 2>&1; then
        echo 'Installing nfs-kernel-server...'
        sudo apt-get update -qq
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nfs-kernel-server
    fi
    sudo install -d /etc/exports.d
    sudo install -m 644 '${HERMES_DIR}/nfs/nature-media.exports' /etc/exports.d/nature-media.exports
    sudo install -d /etc/systemd/system/nfs-server.service.d
    sudo install -m 644 '${HERMES_DIR}/systemd/nfs-server-data-disk.conf' /etc/systemd/system/nfs-server.service.d/nature-data-disk.conf
    sudo systemctl daemon-reload
    sudo systemctl enable --now nfs-server >/dev/null 2>&1
    sudo exportfs -ra
"

# --- qBittorrent policy (malware guard + category paths) ---
# Best-effort: needs the WebUI password in secrets.yaml. The script skips
# cleanly on a first deploy before the permanent password is recorded.
QB_URL="http://10.30.1.57:8080" "${SCRIPT_DIR}/configure-qbittorrent.sh" || \
    echo "WARNING: qBittorrent policy not applied (see message above); re-run ./hermes/configure-qbittorrent.sh once creds are set." >&2

cat <<EOF
Media stack deployed.

qBittorrent WebUI: http://10.30.1.57:8080
Plex:              http://10.30.1.57:32400/web
VPN HTTP proxy:    http://10.30.1.57:8888 (Prowlarr indexer proxy)
NFS export:        10.30.1.57:/mnt/data (cereal media namespace)
Remote dir:        ${HERMES_SSH_HOST}:${HERMES_DIR}
First run? Get the temporary WebUI password with:
  ssh ${HERMES_SSH_HOST} "docker logs qbittorrent 2>&1 | grep -i password"
EOF
