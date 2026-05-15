#!/usr/bin/env bash
# Generate Talos configs from templates + secrets.yaml
# Usage: ./talos/generate-configs.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SECRETS_FILE="${REPO_ROOT}/secrets.yaml"
TEMPLATE_DIR="${SCRIPT_DIR}"
OUTPUT_DIR="${SCRIPT_DIR}/generated"

# Check dependencies
if ! command -v yq &>/dev/null; then
    echo "ERROR: yq is required but not installed."
    echo "Install with: brew install yq  (or go install github.com/mikefarah/yq/v4@latest)"
    exit 1
fi

# Check secrets file exists
if [[ ! -f "${SECRETS_FILE}" ]]; then
    echo "ERROR: secrets.yaml not found at ${SECRETS_FILE}"
    echo "Copy talos/secrets.yaml.template to secrets.yaml and fill in your values."
    exit 1
fi

# Create output directory
mkdir -p "${OUTPUT_DIR}"
echo "Generating Talos configs in ${OUTPUT_DIR}/ ..."

# Helper to read a value from secrets.yaml
get_secret() {
    local path="$1"
    yq eval "${path}" "${SECRETS_FILE}"
}

# Read all secrets into variables
MACHINE_TOKEN=$(get_secret '.talos.machineToken')
CLUSTER_TOKEN=$(get_secret '.talos.clusterToken')
CLUSTER_ID=$(get_secret '.talos.clusterId')
CLUSTER_SECRET=$(get_secret '.talos.clusterSecret')
SECRETBOX_KEY=$(get_secret '.talos.secretboxEncryptionSecret')
MACHINE_CA_CRT=$(get_secret '.talos.machineCA.crt')
MACHINE_CA_KEY=$(get_secret '.talos.machineCA.key')
CLUSTER_CA_CRT=$(get_secret '.talos.clusterCA.crt')
CLUSTER_CA_KEY=$(get_secret '.talos.clusterCA.key')
AGG_CA_CRT=$(get_secret '.talos.aggregatorCA.crt')
AGG_CA_KEY=$(get_secret '.talos.aggregatorCA.key')
ETCD_CA_CRT=$(get_secret '.talos.etcdCA.crt')
ETCD_CA_KEY=$(get_secret '.talos.etcdCA.key')
SA_KEY=$(get_secret '.talos.serviceAccount.key')
CLIENT_CRT=$(get_secret '.talos.client.crt')
CLIENT_KEY=$(get_secret '.talos.client.key')

# Generate controlplane.yaml
sed -e "s|\${TALOS_MACHINE_TOKEN}|${MACHINE_TOKEN}|g" \
    -e "s|\${TALOS_CLUSTER_TOKEN}|${CLUSTER_TOKEN}|g" \
    -e "s|\${TALOS_CLUSTER_ID}|${CLUSTER_ID}|g" \
    -e "s|\${TALOS_CLUSTER_SECRET}|${CLUSTER_SECRET}|g" \
    -e "s|\${TALOS_SECRETBOX_KEY}|${SECRETBOX_KEY}|g" \
    -e "s|\${TALOS_MACHINE_CA_CRT}|${MACHINE_CA_CRT}|g" \
    -e "s|\${TALOS_MACHINE_CA_KEY}|${MACHINE_CA_KEY}|g" \
    -e "s|\${TALOS_CLUSTER_CA_CRT}|${CLUSTER_CA_CRT}|g" \
    -e "s|\${TALOS_CLUSTER_CA_KEY}|${CLUSTER_CA_KEY}|g" \
    -e "s|\${TALOS_AGGREGATOR_CA_CRT}|${AGG_CA_CRT}|g" \
    -e "s|\${TALOS_AGGREGATOR_CA_KEY}|${AGG_CA_KEY}|g" \
    -e "s|\${TALOS_ETCD_CA_CRT}|${ETCD_CA_CRT}|g" \
    -e "s|\${TALOS_ETCD_CA_KEY}|${ETCD_CA_KEY}|g" \
    -e "s|\${TALOS_SERVICE_ACCOUNT_KEY}|${SA_KEY}|g" \
    "${TEMPLATE_DIR}/controlplane.yaml" > "${OUTPUT_DIR}/controlplane.yaml"

# Generate base worker.yaml
sed -e "s|\${TALOS_MACHINE_TOKEN}|${MACHINE_TOKEN}|g" \
    -e "s|\${TALOS_CLUSTER_TOKEN}|${CLUSTER_TOKEN}|g" \
    -e "s|\${TALOS_CLUSTER_ID}|${CLUSTER_ID}|g" \
    -e "s|\${TALOS_CLUSTER_SECRET}|${CLUSTER_SECRET}|g" \
    -e "s|\${TALOS_MACHINE_CA_CRT}|${MACHINE_CA_CRT}|g" \
    -e "s|\${TALOS_MACHINE_CA_KEY}|${MACHINE_CA_KEY}|g" \
    -e "s|\${TALOS_CLUSTER_CA_CRT}|${CLUSTER_CA_CRT}|g" \
    -e "s|\${TALOS_CLUSTER_CA_KEY}|${CLUSTER_CA_KEY}|g" \
    "${TEMPLATE_DIR}/worker.yaml" > "${OUTPUT_DIR}/worker.yaml"

# Generate per-node worker configs by merging patches
PATCHES_DIR="${TEMPLATE_DIR}/patches"
if [[ -d "${PATCHES_DIR}" ]]; then
    for patch_file in "${PATCHES_DIR}"/*.yaml; do
        [[ -f "${patch_file}" ]] || continue
        node_name="$(basename "${patch_file}" .yaml)"
        echo "  Patching worker config for ${node_name}..."
        yq eval-all 'select(fileIndex == 0) * select(fileIndex == 1)' \
            "${OUTPUT_DIR}/worker.yaml" "${patch_file}" \
            > "${OUTPUT_DIR}/worker-${node_name}.yaml"
    done
fi

# Generate talosconfig (client config — placed in talos/ for direnv auto-loading)
sed -e "s|\${TALOS_MACHINE_CA_CRT}|${MACHINE_CA_CRT}|g" \
    -e "s|\${TALOS_CLIENT_CRT}|${CLIENT_CRT}|g" \
    -e "s|\${TALOS_CLIENT_KEY}|${CLIENT_KEY}|g" \
    "${TEMPLATE_DIR}/talosconfig.template" > "${SCRIPT_DIR}/talosconfig"

echo "Done. Generated files:"
echo "  ${OUTPUT_DIR}/controlplane.yaml"
echo "  ${OUTPUT_DIR}/worker.yaml  (base — all workers)"
if [[ -d "${PATCHES_DIR}" ]]; then
    for patch_file in "${PATCHES_DIR}"/*.yaml; do
        [[ -f "${patch_file}" ]] || continue
        node_name="$(basename "${patch_file}" .yaml)"
        echo "  ${OUTPUT_DIR}/worker-${node_name}.yaml  (patched)"
    done
fi
echo "  ${SCRIPT_DIR}/talosconfig  (auto-loaded by direnv)"
echo ""
echo "WARNING: These files contain real secrets. They are in gitignored directories/files."
echo "Do NOT commit them to git."
