#!/usr/bin/env bash
# Bootstrap Flux GitOps onto the Oracle (OCI K3s) cluster.
# The cluster itself is provisioned by Terraform in this directory and is already
# running — this script only installs Flux and wires it to the Nature repo.
# Idempotent — safe to re-run.
#
# Usage:
#   ./oracle/bootstrap.sh            # Push secrets + install Flux + report
#   ./oracle/bootstrap.sh secrets    # Push oracle secrets only
#   ./oracle/bootstrap.sh flux       # Install/refresh Flux only
#   ./oracle/bootstrap.sh status     # Show Flux reconciliation status
#
# Prereqs: the cluster's kubeconfig must be present at oracle/kubeconfig.yaml
# (see README — fetched from the control plane). KUBECONFIG is set to it here.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
KUBECONFIG="${SCRIPT_DIR}/kubeconfig.yaml"
export KUBECONFIG

CLUSTER="oracle"
FLUX_SYSTEM_DIR="${SCRIPT_DIR}/flux/flux-system"

# --- Colours ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${GREEN}==>${NC} ${BOLD}$*${NC}"; }
warn()  { echo -e "${YELLOW}==> WARNING:${NC} $*"; }
err()   { echo -e "${RED}==> ERROR:${NC} $*" >&2; }
die()   { err "$@"; exit 1; }

# --- Prerequisite checks ---
check_prereqs() {
    local missing=()
    command -v kubectl &>/dev/null || missing+=(kubectl)
    command -v yq      &>/dev/null || missing+=(yq)
    if [[ ${#missing[@]} -gt 0 ]]; then
        die "Missing required tools: ${missing[*]}"
    fi

    [[ -f "${REPO_ROOT}/secrets.yaml" ]] || \
        die "secrets.yaml not found at ${REPO_ROOT}/secrets.yaml\n" \
            "    Copy talos/secrets.yaml.template to secrets.yaml and populate it."

    [[ -f "$KUBECONFIG" ]] || \
        die "kubeconfig not found at ${KUBECONFIG}\n" \
            "    Fetch it from the control plane (see oracle/README.md), e.g.:\n" \
            "    ssh opc@\$(terraform output -raw control_plane_public_ip) 'sudo cat /etc/rancher/k3s/k3s.yaml' > kubeconfig.yaml"

    kubectl cluster-info &>/dev/null || \
        die "Cannot reach the cluster with ${KUBECONFIG}. Check the control plane is up and the kubeconfig server IP is correct."
}

# --- Push secrets for this cluster ---
push_secrets() {
    info "Pushing Kubernetes secret(s) for cluster '${CLUSTER}'..."
    # Pushes shared entries (e.g. flux-system) plus any tagged `clusters: [oracle]`.
    bash "${REPO_ROOT}/scripts/secrets.sh" push --cluster "${CLUSTER}"
}

# --- Install / refresh Flux ---
install_flux() {
    [[ -f "${FLUX_SYSTEM_DIR}/gotk-components.yaml" ]] || \
        die "Flux components not found at ${FLUX_SYSTEM_DIR}/gotk-components.yaml"

    # The flux-system GitRepository authenticates with the 'flux-system' secret.
    if ! kubectl -n flux-system get secret flux-system &>/dev/null; then
        warn "flux-system secret not found in the cluster — run './oracle/bootstrap.sh secrets' first."
        warn "Flux will not be able to pull the repo until that secret exists."
    fi

    # Components first (CRDs + controllers), then the sync (GitRepository +
    # Kustomization CRs that depend on those CRDs). Server-side apply avoids the
    # client-side last-applied annotation size limit on the large Flux CRDs.
    info "Applying Flux components (gotk-components.yaml)..."
    kubectl apply --server-side --force-conflicts -f "${FLUX_SYSTEM_DIR}/gotk-components.yaml"

    info "Waiting for Flux CRDs to be established..."
    kubectl wait --for=condition=Established --timeout=120s \
        crd/gitrepositories.source.toolkit.fluxcd.io \
        crd/kustomizations.kustomize.toolkit.fluxcd.io

    info "Applying Flux sync (gotk-sync.yaml → reconciles ./oracle/flux)..."
    kubectl apply --server-side --force-conflicts -f "${FLUX_SYSTEM_DIR}/gotk-sync.yaml"

    info "Waiting for source-controller to be ready..."
    kubectl -n flux-system rollout status deploy/source-controller --timeout=180s || true
}

# --- Report status ---
status() {
    info "Flux sources & kustomizations on '${CLUSTER}':"
    kubectl -n flux-system get gitrepositories,kustomizations 2>/dev/null || \
        warn "Flux not installed yet (no flux-system resources)."
    if command -v flux &>/dev/null; then
        echo
        flux get kustomizations 2>/dev/null || true
    fi
}

# --- Full bootstrap ---
full() {
    check_prereqs
    push_secrets
    install_flux
    echo
    status
    echo
    info "Done. Flux is reconciling ./oracle/flux on the '${CLUSTER}' cluster."
    info "Watch with: KUBECONFIG=${KUBECONFIG} kubectl -n flux-system get kustomizations -w"
}

case "${1:-full}" in
    ""|full)   full ;;
    secrets)   check_prereqs; push_secrets ;;
    flux)      check_prereqs; install_flux; echo; status ;;
    status)    status ;;
    *)         die "Unknown command: $1 (use: full | secrets | flux | status)" ;;
esac
