#!/usr/bin/env bash
# Generate PXE HTTP assets from pxe/images.yaml and pxe/nodes.yaml.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGES_FILE="${SCRIPT_DIR}/images.yaml"
NODES_FILE="${SCRIPT_DIR}/nodes.yaml"
GENERATED_DIR="${SCRIPT_DIR}/generated"
HTTP_DIR="${GENERATED_DIR}/http"
MENUS_DIR="${HTTP_DIR}/menus"

PXE_SERVER_IP="${PXE_SERVER_IP:-10.30.1.20}"
HTTP_PORT="${HTTP_PORT:-8080}"
SERVER_URL="http://${PXE_SERVER_IP}:${HTTP_PORT}"
UNATTENDED=false

usage() {
    cat <<EOF
Usage: $0 [--unattended]

Options:
  --unattended    Generate a Talos menu entry that fetches configs by iPXE MAC.
  -h, --help      Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --unattended)
            UNATTENDED=true
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

validate_unattended_nodes() {
    local count i name mac normalized

    count="$(yaml_value '.nodes | length' "${NODES_FILE}")"
    i=0
    while [[ "${i}" -lt "${count}" ]]; do
        name="$(yaml_value ".nodes[${i}].name" "${NODES_FILE}")"
        mac="$(yaml_value ".nodes[${i}].mac" "${NODES_FILE}")"
        normalized="$(normalize_mac "${mac}")"

        if [[ -z "${mac}" || "${mac}" == "null" || "${normalized}" == "todo" ]]; then
            echo "ERROR: unattended mode requires a real MAC for node ${name} in ${NODES_FILE}." >&2
            exit 1
        fi

        if [[ ! "${normalized}" =~ ^([0-9a-f]{2}:){5}[0-9a-f]{2}$ ]]; then
            echo "ERROR: invalid MAC for node ${name}: ${mac}" >&2
            exit 1
        fi

        i=$((i + 1))
    done
}

write_talos_menu() {
    local id="$1"
    local label="$2"
    local config_arg="${3:-}"
    local version schematic kernel_args

    version="$(yaml_value '.talos.version' "${IMAGES_FILE}")"
    schematic="$(yaml_value '.talos.schematic' "${IMAGES_FILE}")"
    kernel_args="$(yaml_value '.talos.kernelArgs | join(" ")' "${IMAGES_FILE}")"

    if [[ -z "${version}" || "${version}" == "null" ]]; then
        echo "ERROR: talos.version is required in ${IMAGES_FILE}." >&2
        exit 1
    fi

    if [[ -z "${schematic}" || "${schematic}" == "null" ]]; then
        echo "ERROR: talos.schematic is required in ${IMAGES_FILE}." >&2
        exit 1
    fi

    cat > "${MENUS_DIR}/${id}.ipxe" <<EOF
#!ipxe
echo Booting ${label}
imgfree
kernel https://factory.talos.dev/image/${schematic}/${version}/kernel-amd64 ${kernel_args}${config_arg}
initrd https://factory.talos.dev/image/${schematic}/${version}/initramfs-amd64.xz
boot
EOF
}

write_ipxe_chain_menu() {
    local id="$1"
    local label="$2"
    local url="$3"

    if [[ -z "${url}" || "${url}" == "null" ]]; then
        echo "ERROR: image ${id} is type ipxe-chain but has no url." >&2
        exit 1
    fi

    cat > "${MENUS_DIR}/${id}.ipxe" <<EOF
#!ipxe
echo Chainloading ${label}
chain --replace --autofree ${url} || shell
EOF
}

require_command yq

if [[ ! -f "${IMAGES_FILE}" ]]; then
    echo "ERROR: missing ${IMAGES_FILE}" >&2
    exit 1
fi

if [[ ! -f "${NODES_FILE}" ]]; then
    echo "ERROR: missing ${NODES_FILE}" >&2
    exit 1
fi

yq eval '.' "${IMAGES_FILE}" >/dev/null
yq eval '.' "${NODES_FILE}" >/dev/null

if [[ "${UNATTENDED}" == true ]]; then
    validate_unattended_nodes
fi

rm -rf "${HTTP_DIR}"
mkdir -p "${MENUS_DIR}"

cat > "${HTTP_DIR}/boot.ipxe" <<EOF
#!ipxe
:start
set menu-timeout 8000
menu Nature PXE boot
EOF

image_count="$(yaml_value '.images | length' "${IMAGES_FILE}")"
i=0
while [[ "${i}" -lt "${image_count}" ]]; do
    id="$(yaml_value ".images[${i}].id" "${IMAGES_FILE}")"
    label="$(yaml_value ".images[${i}].label" "${IMAGES_FILE}")"
    type="$(yaml_value ".images[${i}].type" "${IMAGES_FILE}")"

    if [[ -z "${id}" || "${id}" == "null" ]]; then
        echo "ERROR: images[${i}].id is required in ${IMAGES_FILE}." >&2
        exit 1
    fi

    if [[ -z "${label}" || "${label}" == "null" ]]; then
        echo "ERROR: images[${i}].label is required in ${IMAGES_FILE}." >&2
        exit 1
    fi

    case "${type}" in
        talos)
            write_talos_menu "${id}" "${label}"
            ;;
        ipxe-chain)
            url="$(yaml_value ".images[${i}].url" "${IMAGES_FILE}")"
            write_ipxe_chain_menu "${id}" "${label}" "${url}"
            ;;
        *)
            echo "ERROR: unsupported image type for ${id}: ${type}" >&2
            exit 1
            ;;
    esac

    echo "item ${id} ${label}" >> "${HTTP_DIR}/boot.ipxe"
    i=$((i + 1))
done

if [[ "${UNATTENDED}" == true ]]; then
    write_talos_menu "talos-unattended" "Talos unattended reinstall" " talos.config=${SERVER_URL}/configs/\${mac}.yaml"
    echo "item talos-unattended Talos unattended reinstall (MAC matched)" >> "${HTTP_DIR}/boot.ipxe"
fi

cat >> "${HTTP_DIR}/boot.ipxe" <<EOF
item shell iPXE shell
item reboot Reboot
choose --timeout \${menu-timeout} --default talos-maintenance target || goto shell
iseq \${target} shell && goto shell ||
iseq \${target} reboot && reboot ||
chain --replace --autofree ${SERVER_URL}/menus/\${target}.ipxe || goto shell
goto start

:shell
shell
goto start
EOF

echo "Generated PXE assets in ${GENERATED_DIR}"
