#!/usr/bin/env bash
# Manage Kubernetes secrets for the Nature homelab.
#
# All secrets live in the single root secrets.yaml (gitignored) under the
# `kubernetes.secrets` key.  Values are stored as plaintext; the script
# base64-encodes them when constructing K8s manifests for `kubectl apply`.
#
# Multi-cluster: each entry may carry an optional `clusters: [name, ...]` list.
# An entry WITHOUT a `clusters` field is shared (pushed to every cluster). With
# `--cluster NAME`, push applies only shared entries plus those whose `clusters`
# list contains NAME. Without `--cluster`, all entries are pushed (legacy).
#
# Usage:
#   ./scripts/secrets.sh create <name> -n <ns> [--type <type>] --from-literal key=val ...
#   ./scripts/secrets.sh import <file>
#   ./scripts/secrets.sh push [--dry-run] [--cluster <name>] [name]
#   ./scripts/secrets.sh list
#   ./scripts/secrets.sh show <name>
#   ./scripts/secrets.sh delete <name>
#   ./scripts/secrets.sh validate

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${REPO_ROOT}/scripts/secrets-path.sh"

# --- Colours ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${GREEN}==>${NC} ${BOLD}$*${NC}"; }
warn()  { echo -e "${YELLOW}==> WARNING:${NC} $*"; }
err()   { echo -e "${RED}==> ERROR:${NC} $*" >&2; }
die()   { echo -e "${RED}==> ERROR:${NC} $*" >&2; exit 1; }

# --- Dependency checks ---
require_yq() {
    command -v yq &>/dev/null || die "yq is required. Install with: brew install yq"
}

require_kubectl() {
    command -v kubectl &>/dev/null || die "kubectl is required."
}

check_secrets_file() {
    [[ -f "$SECRETS_FILE" ]] || die "secrets.yaml not found at ${SECRETS_FILE}\n" \
        "    Copy talos/secrets.yaml.template to secrets.yaml and populate it."
}

# Ensure the kubernetes.secrets key exists in secrets.yaml
ensure_k8s_section() {
    local has_section
    has_section="$(yq eval '.kubernetes.secrets' "$SECRETS_FILE")"
    if [[ "$has_section" == "null" ]]; then
        yq -i eval '.kubernetes.secrets = []' "$SECRETS_FILE"
    fi
}

# Count how many secrets match a given name
count_by_name() {
    local name="$1"
    yq eval "[.kubernetes.secrets[] | select(.name == \"${name}\")] | length" "$SECRETS_FILE"
}

# Build a K8s Secret manifest from an entry in secrets.yaml.
# Reads the entry at the given array index and outputs a valid K8s Secret YAML
# with base64-encoded data values.
build_manifest() {
    local idx="$1"
    local s_name s_ns s_type
    s_name="$(yq eval ".kubernetes.secrets[${idx}].name" "$SECRETS_FILE")"
    s_ns="$(yq eval ".kubernetes.secrets[${idx}].namespace // \"default\"" "$SECRETS_FILE")"
    s_type="$(yq eval ".kubernetes.secrets[${idx}].type // \"Opaque\"" "$SECRETS_FILE")"

    # Start manifest
    echo "apiVersion: v1"
    echo "kind: Secret"
    echo "metadata:"
    echo "  name: ${s_name}"
    echo "  namespace: ${s_ns}"
    echo "type: ${s_type}"
    echo "data:"

    # Iterate data keys — yq outputs keys one per line
    local keys
    keys="$(yq eval ".kubernetes.secrets[${idx}].data | keys | .[]" "$SECRETS_FILE")"
    while IFS= read -r key; do
        [[ -n "$key" ]] || continue
        local val
        val="$(yq eval ".kubernetes.secrets[${idx}].data[\"${key}\"]" "$SECRETS_FILE")"
        local encoded
        encoded="$(printf '%s' "$val" | base64)"
        echo "  ${key}: ${encoded}"
    done <<< "$keys"
}

# --- Commands ---

cmd_create() {
    require_yq
    check_secrets_file

    local name="" namespace="default" secret_type="Opaque"
    local -a literals=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n|--namespace)   namespace="$2"; shift 2 ;;
            --type)           secret_type="$2"; shift 2 ;;
            --from-literal)   literals+=("$2"); shift 2 ;;
            -*)               die "Unknown flag: $1" ;;
            *)
                if [[ -z "$name" ]]; then
                    name="$1"; shift
                else
                    die "Unexpected argument: $1"
                fi
                ;;
        esac
    done

    [[ -n "$name" ]]            || die "Usage: $0 create <name> -n <namespace> --from-literal key=val ..."
    [[ ${#literals[@]} -gt 0 ]] || die "At least one --from-literal key=val is required."

    ensure_k8s_section

    # Check for duplicate
    local existing
    existing="$(count_by_name "$name")"
    if [[ "$existing" -gt 0 ]]; then
        die "Secret '${name}' already exists. Delete it first or choose a different name."
    fi

    # Build the new entry as a yq expression
    local entry="{\"name\": \"${name}\", \"namespace\": \"${namespace}\", \"type\": \"${secret_type}\", \"data\": {}}"
    yq -i eval ".kubernetes.secrets += [${entry}]" "$SECRETS_FILE"

    # Find the index of the entry we just added (last one)
    local idx
    idx="$(yq eval '.kubernetes.secrets | length - 1' "$SECRETS_FILE")"

    # Add each literal as a data key (use strenv for safe quoting)
    for literal in "${literals[@]}"; do
        local key="${literal%%=*}"
        local val="${literal#*=}"
        [[ "$literal" == *=* ]] || die "Invalid literal (must be key=val): ${literal}"
        YQ_VAL="$val" yq -i eval ".kubernetes.secrets[${idx}].data[\"${key}\"] = strenv(YQ_VAL)" "$SECRETS_FILE"
    done

    info "Created secret '${name}' in namespace '${namespace}' (type: ${secret_type})"
}

cmd_import() {
    require_yq
    check_secrets_file

    local file="${1:?Usage: $0 import <file>}"
    [[ -f "$file" ]] || die "File not found: ${file}"

    # Validate it looks like a Secret
    local kind
    kind="$(yq eval '.kind' "$file")"
    [[ "$kind" == "Secret" ]] || die "File is not a Kubernetes Secret (kind=${kind})"

    local s_name s_ns s_type
    s_name="$(yq eval '.metadata.name' "$file")"
    s_ns="$(yq eval '.metadata.namespace // "default"' "$file")"
    s_type="$(yq eval '.type // "Opaque"' "$file")"

    ensure_k8s_section

    # Check for duplicate
    local existing
    existing="$(count_by_name "$s_name")"
    if [[ "$existing" -gt 0 ]]; then
        die "Secret '${s_name}' already exists. Delete it first."
    fi

    # Add the entry
    local entry="{\"name\": \"${s_name}\", \"namespace\": \"${s_ns}\", \"type\": \"${s_type}\", \"data\": {}}"
    yq -i eval ".kubernetes.secrets += [${entry}]" "$SECRETS_FILE"

    local idx
    idx="$(yq eval '.kubernetes.secrets | length - 1' "$SECRETS_FILE")"

    # Import data keys — decode base64 values back to plaintext for storage
    local data_key
    local keys
    keys="$(yq eval '.data | keys | .[]' "$file")"
    while IFS= read -r data_key; do
        [[ -n "$data_key" ]] || continue
        local encoded_val
        encoded_val="$(yq eval ".data[\"${data_key}\"]" "$file")"
        local decoded_val
        decoded_val="$(printf '%s' "$encoded_val" | base64 -d 2>/dev/null || printf '%s' "$encoded_val")"
        YQ_VAL="$decoded_val" yq -i eval ".kubernetes.secrets[${idx}].data[\"${data_key}\"] = strenv(YQ_VAL)" "$SECRETS_FILE"
    done <<< "$keys"

    info "Imported secret '${s_name}' from ${file} (values stored as plaintext)"
}

cmd_push() {
    require_yq
    require_kubectl
    check_secrets_file

    local dry_run=false
    local target_name=""
    local cluster=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run) dry_run=true; shift ;;
            --cluster) cluster="${2:?--cluster requires a name}"; shift 2 ;;
            -*)        die "Unknown flag: $1" ;;
            *)         target_name="$1"; shift ;;
        esac
    done

    local count
    count="$(yq eval '.kubernetes.secrets | length // 0' "$SECRETS_FILE")"
    if [[ "$count" -eq 0 ]]; then
        warn "No Kubernetes secrets defined in secrets.yaml."
        return
    fi

    [[ -n "$cluster" ]] && info "Filtering for cluster '${cluster}' (shared entries always included)."

    local pushed=0
    for ((i = 0; i < count; i++)); do
        local s_name
        s_name="$(yq eval ".kubernetes.secrets[${i}].name" "$SECRETS_FILE")"

        # If targeting a specific secret, skip non-matches
        if [[ -n "$target_name" && "$s_name" != "$target_name" ]]; then
            continue
        fi

        # Cluster filter: an entry with no `clusters` field is shared (pushed
        # everywhere). If it has one, the target cluster must be listed.
        if [[ -n "$cluster" ]]; then
            local entry_clusters
            entry_clusters="$(yq eval ".kubernetes.secrets[${i}].clusters // [] | .[]" "$SECRETS_FILE")"
            if [[ -n "$entry_clusters" ]] && ! grep -qxF "$cluster" <<< "$entry_clusters"; then
                continue
            fi
        fi

        # Ensure target namespace exists before applying
        local s_ns
        s_ns="$(yq eval ".kubernetes.secrets[${i}].namespace // \"default\"" "$SECRETS_FILE")"
        if [[ "$dry_run" == "false" && "$s_ns" != "default" ]]; then
            if ! kubectl get namespace "$s_ns" &>/dev/null 2>&1; then
                info "Creating namespace '${s_ns}'..."
                kubectl create namespace "$s_ns" 2>/dev/null || true
            fi
        fi

        local manifest
        manifest="$(build_manifest "$i")"

        if [[ "$dry_run" == "true" ]]; then
            info "[dry-run] Would apply secret '${s_name}':"
            echo "$manifest"
            echo "---"
        else
            info "Applying secret '${s_name}'..."
            echo "$manifest" | kubectl apply --server-side -f -
        fi
        pushed=$((pushed + 1))
    done

    if [[ -n "$target_name" && "$pushed" -eq 0 ]]; then
        die "Secret '${target_name}' not found in secrets.yaml"
    fi

    if [[ "$dry_run" == "true" ]]; then
        info "[dry-run] ${pushed} secret(s) would be applied."
    else
        info "${pushed} secret(s) applied."
    fi
}

cmd_list() {
    require_yq
    check_secrets_file

    local count
    count="$(yq eval '.kubernetes.secrets | length // 0' "$SECRETS_FILE")"
    if [[ "$count" -eq 0 ]]; then
        warn "No Kubernetes secrets defined in secrets.yaml."
        echo "  Create secrets with: $0 create <name> -n <ns> --from-literal key=val"
        return
    fi

    printf "${BOLD}%-26s %-16s %-14s %-14s KEYS${NC}\n" "NAME" "NAMESPACE" "TYPE" "CLUSTERS"
    for ((i = 0; i < count; i++)); do
        local s_name s_ns s_type s_clusters s_keys
        s_name="$(yq eval ".kubernetes.secrets[${i}].name" "$SECRETS_FILE")"
        s_ns="$(yq eval ".kubernetes.secrets[${i}].namespace // \"default\"" "$SECRETS_FILE")"
        s_type="$(yq eval ".kubernetes.secrets[${i}].type // \"Opaque\"" "$SECRETS_FILE")"
        s_clusters="$(yq eval ".kubernetes.secrets[${i}].clusters // [\"(all)\"] | join(\",\")" "$SECRETS_FILE")"
        s_keys="$(yq eval ".kubernetes.secrets[${i}].data | keys | join(\", \")" "$SECRETS_FILE")"
        printf "%-26s %-16s %-14s %-14s %s\n" "$s_name" "$s_ns" "$s_type" "$s_clusters" "$s_keys"
    done
}

cmd_show() {
    require_yq
    check_secrets_file

    local name="${1:?Usage: $0 show <name>}"

    local count
    count="$(count_by_name "$name")"
    if [[ "$count" -eq 0 ]]; then
        die "Secret '${name}' not found in secrets.yaml"
    fi

    # Find the index
    local total
    total="$(yq eval '.kubernetes.secrets | length' "$SECRETS_FILE")"
    for ((i = 0; i < total; i++)); do
        local s_name
        s_name="$(yq eval ".kubernetes.secrets[${i}].name" "$SECRETS_FILE")"
        if [[ "$s_name" == "$name" ]]; then
            yq eval ".kubernetes.secrets[${i}]" "$SECRETS_FILE"
            return
        fi
    done
}

cmd_delete() {
    require_yq
    check_secrets_file

    local name="${1:?Usage: $0 delete <name>}"

    local count
    count="$(count_by_name "$name")"
    if [[ "$count" -eq 0 ]]; then
        die "Secret '${name}' not found in secrets.yaml"
    fi

    yq -i eval "del(.kubernetes.secrets[] | select(.name == \"${name}\"))" "$SECRETS_FILE"

    info "Deleted secret '${name}' from secrets.yaml"
    warn "Secret may still exist in cluster. Remove with: kubectl delete secret ${name}"
}

cmd_validate() {
    require_yq
    check_secrets_file

    local count
    count="$(yq eval '.kubernetes.secrets | length // 0' "$SECRETS_FILE")"
    if [[ "$count" -eq 0 ]]; then
        info "No Kubernetes secrets defined in secrets.yaml — nothing to validate."
        return
    fi

    local errors=0
    for ((i = 0; i < count; i++)); do
        local s_name s_ns s_data_count
        s_name="$(yq eval ".kubernetes.secrets[${i}].name" "$SECRETS_FILE")"
        s_ns="$(yq eval ".kubernetes.secrets[${i}].namespace // \"default\"" "$SECRETS_FILE")"
        s_data_count="$(yq eval ".kubernetes.secrets[${i}].data | length // 0" "$SECRETS_FILE")"

        if [[ -z "$s_name" || "$s_name" == "null" ]]; then
            err "Entry ${i}: missing 'name'"
            errors=$((errors + 1))
        fi
        if [[ "$s_data_count" -eq 0 ]]; then
            err "Entry ${i} (${s_name}): 'data' is empty or missing"
            errors=$((errors + 1))
        fi
    done

    if [[ $errors -gt 0 ]]; then
        die "Validation failed with ${errors} error(s)."
    fi

    info "Valid: ${count} secret(s) in secrets.yaml"
}

# --- Main ---
case "${1:-}" in
    create)   shift; cmd_create "$@" ;;
    import)   shift; cmd_import "$@" ;;
    push)     shift; cmd_push "$@" ;;
    list)     cmd_list ;;
    show)     shift; cmd_show "$@" ;;
    delete)   shift; cmd_delete "$@" ;;
    validate) cmd_validate ;;
    *)
        echo "Usage: $0 <command> [args]"
        echo ""
        echo "Commands:"
        echo "  create <name> -n <ns> [--type <t>] --from-literal k=v ...   Create a secret"
        echo "  import <file>                                                Import a K8s Secret YAML"
        echo "  push [--dry-run] [--cluster <name>] [name]                   Push secrets to cluster"
        echo "  list                                                         List managed secrets"
        echo "  show <name>                                                  Show a secret's values"
        echo "  delete <name>                                                Remove a secret"
        echo "  validate                                                     Validate all entries"
        echo ""
        echo "Secrets are stored in secrets.yaml under kubernetes.secrets[]."
        echo "Values are kept as plaintext; base64-encoding happens at push time."
        exit 1
        ;;
esac
