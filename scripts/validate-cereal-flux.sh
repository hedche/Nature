#!/usr/bin/env bash
# Validate Flux-managed Kubernetes manifests for the cereal cluster.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUBERNETES_DIR="${REPO_ROOT}/kubernetes"
SCHEMA_DIR="$(mktemp -d)"

cleanup() {
    rm -rf "$SCHEMA_DIR"
}
trap cleanup EXIT

die() {
    echo "ERROR: $*" >&2
    exit 1
}

info() {
    echo "==> $*"
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "$1 is required"
}

validate_yaml_syntax() {
    info "Validating YAML syntax"
    while IFS= read -r -d '' file; do
        yq eval 'true' "$file" >/dev/null
    done < <(find "$KUBERNETES_DIR" -type f \( -name '*.yaml' -o -name '*.yml' \) -print0)
}

download_flux_schemas() {
    info "Downloading Flux OpenAPI schemas"
    mkdir -p "$SCHEMA_DIR/master-standalone-strict"
    curl -sSfL https://github.com/fluxcd/flux2/releases/latest/download/crd-schemas.tar.gz \
        | tar zxf - -C "$SCHEMA_DIR/master-standalone-strict"
}

validate_kustomize_overlays() {
    info "Validating Kustomize overlays"
    while IFS= read -r -d '' file; do
        local dir
        dir="$(dirname "$file")"
        echo "    ${dir#"$REPO_ROOT"/}"
        kustomize build "$dir" --load-restrictor=LoadRestrictionsNone \
            | kubeconform \
                -strict \
                -ignore-missing-schemas \
                -skip Secret \
                -schema-location default \
                -schema-location "$SCHEMA_DIR" \
                -summary
    done < <(find "$KUBERNETES_DIR" -type f -name kustomization.yaml -print0)
}

main() {
    require_cmd curl
    require_cmd find
    require_cmd kubeconform
    require_cmd kustomize
    require_cmd tar
    require_cmd yq

    validate_yaml_syntax
    download_flux_schemas
    validate_kustomize_overlays
# --- remote_write allow-list must not contain folded-scalar spaces -------------
# A YAML folded scalar (>-) joins lines with a space, and Prometheus relabel
# regexes are fully anchored, so any alternative that begins a line becomes
# " name" and silently never matches. This shipped once: 28 of 67 names were
# dead, including node_power_supply_online and ceph_health_status.
check_remote_write_allowlist() {
    local f="kubernetes/monitoring/helmrelease.yaml"
    [[ -f "$f" ]] || return 0
    local rx
    rx="$(yq eval '.spec.values.prometheus.prometheusSpec.remoteWrite[0].writeRelabelConfigs[0].regex // ""' "$f")"
    [[ -n "$rx" && "$rx" != "null" ]] || return 0
    if [[ "$rx" == *" "* ]]; then
        echo "ERROR: remote_write allow-list regex contains a space." >&2
        echo "       Keep it on ONE line — a folded scalar makes alternatives unmatchable." >&2
        echo "       Offending: $(printf '%s' "$rx" | tr '|' '\n' | grep '^ ' | head -5 | tr '\n' ' ')" >&2
        return 1
    fi
    echo "  remote_write allow-list: $(printf '%s' "$rx" | tr '|' '\n' | wc -l | tr -d ' ') names, no folded spaces"
}

check_remote_write_allowlist || exit 1


    info "All cereal Flux validations passed"
}

main "$@"
