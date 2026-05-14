#!/usr/bin/env bash
# Idempotently deploy the Nature PXE stack to the QNAP NAS.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
NODES_FILE="${SCRIPT_DIR}/nodes.yaml"

QNAP_SSH_HOST="${QNAP_SSH_HOST:-admin@10.30.1.20}"
QNAP_PXE_DIR="${QNAP_PXE_DIR:-/share/Container/nature-pxe}"
COMPOSE_PROJECT="${COMPOSE_PROJECT:-nature-pxe}"
PXE_SERVER_IP="${PXE_SERVER_IP:-10.30.1.20}"
HTTP_PORT="${HTTP_PORT:-8080}"

INCLUDE_TALOS_CONFIGS=false
DRY_RUN=false
ASSUME_RISK=false

usage() {
    cat <<EOF
Usage: $0 [options]

Options:
  --host <ssh-host>                  SSH target for QNAP (default: ${QNAP_SSH_HOST})
  --remote-dir <path>                Remote managed directory (default: ${QNAP_PXE_DIR})
  --project <name>                   Compose project name (default: ${COMPOSE_PROJECT})
  --include-talos-configs            Copy generated Talos configs into PXE HTTP assets.
  --yes-risk-expose-talos-configs    Skip interactive warning for --include-talos-configs.
  --dry-run                          Generate and show rsync changes without modifying QNAP.
  -h, --help                         Show this help.

Environment:
  QNAP_SSH_HOST, QNAP_PXE_DIR, COMPOSE_PROJECT, PXE_SERVER_IP, HTTP_PORT
EOF
}

require_command() {
    if ! command -v "$1" &>/dev/null; then
        echo "ERROR: $1 is required but not installed." >&2
        exit 1
    fi
}

yaml_value() {
    yq eval -r "$1" "$2"
}

normalize_mac() {
    echo "$1" | tr '[:upper:]' '[:lower:]' | tr '-' ':'
}

confirm_talos_config_exposure() {
    if [[ "${ASSUME_RISK}" == true ]]; then
        return
    fi

    if [[ ! -t 0 ]]; then
        echo "ERROR: --include-talos-configs requires --yes-risk-expose-talos-configs in non-interactive mode." >&2
        exit 1
    fi

    cat <<EOF
WARNING: --include-talos-configs will serve generated Talos machine configs over HTTP from the PXE server.
These configs contain cluster secrets. Only use this on a trusted provisioning network, and redeploy without
this flag immediately after reinstalling nodes.

Type EXPOSE TALOS CONFIGS to continue:
EOF
    read -r response
    if [[ "${response}" != "EXPOSE TALOS CONFIGS" ]]; then
        echo "Aborted." >&2
        exit 1
    fi
}

copy_talos_configs() {
    local configs_dir count i name mac normalized config source

    bash "${REPO_ROOT}/talos/generate-configs.sh"

    configs_dir="${SCRIPT_DIR}/generated/http/configs"
    mkdir -p "${configs_dir}"

    count="$(yaml_value '.nodes | length' "${NODES_FILE}")"
    i=0
    while [[ "${i}" -lt "${count}" ]]; do
        name="$(yaml_value ".nodes[${i}].name" "${NODES_FILE}")"
        mac="$(yaml_value ".nodes[${i}].mac" "${NODES_FILE}")"
        config="$(yaml_value ".nodes[${i}].talosConfig" "${NODES_FILE}")"
        normalized="$(normalize_mac "${mac}")"
        source="${REPO_ROOT}/talos/generated/${config}"

        if [[ ! -f "${source}" ]]; then
            echo "ERROR: expected generated Talos config not found: ${source}" >&2
            exit 1
        fi

        cp "${source}" "${configs_dir}/${normalized}.yaml"
        cp "${source}" "${configs_dir}/${name}.yaml"
        i=$((i + 1))
    done
}

validate_remote_path() {
    case "${QNAP_PXE_DIR}" in
        */nature-pxe) ;;
        *)
            echo "ERROR: refusing to rsync --delete to a path that does not end with nature-pxe: ${QNAP_PXE_DIR}" >&2
            exit 1
            ;;
    esac
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --host)
            QNAP_SSH_HOST="$2"
            shift 2
            ;;
        --remote-dir)
            QNAP_PXE_DIR="$2"
            shift 2
            ;;
        --project)
            COMPOSE_PROJECT="$2"
            shift 2
            ;;
        --include-talos-configs)
            INCLUDE_TALOS_CONFIGS=true
            shift
            ;;
        --yes-risk-expose-talos-configs)
            ASSUME_RISK=true
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

if [[ "${INCLUDE_TALOS_CONFIGS}" == true ]]; then
    confirm_talos_config_exposure
    PXE_SERVER_IP="${PXE_SERVER_IP}" HTTP_PORT="${HTTP_PORT}" "${SCRIPT_DIR}/generate-assets.sh" --unattended
    copy_talos_configs
else
    PXE_SERVER_IP="${PXE_SERVER_IP}" HTTP_PORT="${HTTP_PORT}" "${SCRIPT_DIR}/generate-assets.sh"
fi

if [[ "${DRY_RUN}" == true ]]; then
    rsync_mode=(--dry-run --itemize-changes)
else
    ssh "${QNAP_SSH_HOST}" "mkdir -p '${QNAP_PXE_DIR}' && touch '${QNAP_PXE_DIR}/.nature-pxe-managed'"
    rsync_mode=()
fi

rsync -az --delete \
    --filter='P .nature-pxe-managed' \
    --exclude='.deploy/' \
    --exclude='assets/' \
    "${rsync_mode[@]}" \
    "${SCRIPT_DIR}/" "${QNAP_SSH_HOST}:${QNAP_PXE_DIR}/"

if [[ "${DRY_RUN}" == true ]]; then
    echo "Dry run complete. No changes were pushed to ${QNAP_SSH_HOST}:${QNAP_PXE_DIR}."
    exit 0
fi

ssh "${QNAP_SSH_HOST}" "
    set -eu
    cd '${QNAP_PXE_DIR}'
    test -f .nature-pxe-managed
    if docker compose version >/dev/null 2>&1; then
        compose='docker compose'
    elif command -v docker-compose >/dev/null 2>&1; then
        compose='docker-compose'
    else
        echo 'ERROR: Docker Compose was not found on the QNAP host.' >&2
        exit 1
    fi
    \${compose} -p '${COMPOSE_PROJECT}' config >/dev/null
    \${compose} -p '${COMPOSE_PROJECT}' up -d --build --remove-orphans
    \${compose} -p '${COMPOSE_PROJECT}' ps
"

cat <<EOF
PXE stack deployed.

HTTP menu: http://${PXE_SERVER_IP}:${HTTP_PORT}/boot.ipxe
Remote dir: ${QNAP_SSH_HOST}:${QNAP_PXE_DIR}
EOF

