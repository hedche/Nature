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
    info "All cereal Flux validations passed"
}

main "$@"
