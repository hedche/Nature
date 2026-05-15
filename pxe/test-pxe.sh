#!/usr/bin/env bash
# Validate the deployed PXE stack from the workstation.

set -euo pipefail

QNAP_SSH_HOST="${QNAP_SSH_HOST:-admin@10.30.1.20}"
QNAP_PXE_DIR="${QNAP_PXE_DIR:-/share/Container/nature-pxe}"
COMPOSE_PROJECT="${COMPOSE_PROJECT:-nature-pxe}"
PXE_SERVER_IP="${PXE_SERVER_IP:-10.30.1.20}"
HTTP_PORT="${HTTP_PORT:-8080}"
SKIP_SSH=false

usage() {
    cat <<EOF
Usage: $0 [options]

Options:
  --host <ssh-host>      SSH target for QNAP (default: ${QNAP_SSH_HOST})
  --skip-ssh             Only test HTTP/TFTP from this machine.
  -h, --help             Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --host)
            QNAP_SSH_HOST="$2"
            shift 2
            ;;
        --skip-ssh)
            SKIP_SSH=true
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

echo "Checking HTTP boot menu..."
curl -fsS "http://${PXE_SERVER_IP}:${HTTP_PORT}/boot.ipxe" >/dev/null

echo "Checking Talos menu..."
curl -fsS "http://${PXE_SERVER_IP}:${HTTP_PORT}/menus/talos-maintenance.ipxe" >/dev/null

if command -v tftp &>/dev/null; then
    tmpdir="$(mktemp -d)"
    trap 'rm -rf "${tmpdir}"' EXIT
    echo "Checking TFTP iPXE binary..."
    (
        cd "${tmpdir}"
        printf 'get ipxe.efi\nquit\n' | tftp "${PXE_SERVER_IP}" >/dev/null
        test -s ipxe.efi
    )
else
    echo "Skipping TFTP check: tftp command not installed."
fi

if [[ "${SKIP_SSH}" != true ]]; then
    echo "Checking QNAP Compose service..."
    ssh "${QNAP_SSH_HOST}" "
        set -eu
        cd '${QNAP_PXE_DIR}'
        if docker compose version >/dev/null 2>&1; then
            docker compose -p '${COMPOSE_PROJECT}' ps
        else
            docker-compose -p '${COMPOSE_PROJECT}' ps
        fi
    "
fi

echo "PXE validation passed."

