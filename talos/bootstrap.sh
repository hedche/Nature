#!/usr/bin/env bash
# Bootstrap the cereal Talos Kubernetes cluster.
#
# Usage:
#   ./talos/bootstrap.sh                  # Full cluster bootstrap
#   ./talos/bootstrap.sh apply <node>     # Apply config to a single node
#   ./talos/bootstrap.sh status           # Check cluster health
#
# Nodes:
#   controlplane  10.30.1.50
#   snap          10.30.1.51  (worker)
#   crackle       10.30.1.52  (worker)
#   pop           10.30.1.53  (worker)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
GENERATED="${SCRIPT_DIR}/generated"
TALOSCONFIG="${SCRIPT_DIR}/talosconfig"

# --- Node map (bash 3.2 compatible) ---
ALL_NODES="controlplane snap crackle pop"
WORKERS="snap crackle pop"

node_ip() {
    case "$1" in
        controlplane) echo "10.30.1.50" ;;
        snap)          echo "10.30.1.51" ;;
        crackle)       echo "10.30.1.52" ;;
        pop)           echo "10.30.1.53" ;;
        *)             return 1 ;;
    esac
}

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
    command -v talosctl &>/dev/null || missing+=(talosctl)
    command -v yq       &>/dev/null || missing+=(yq)
    command -v kubectl  &>/dev/null || missing+=(kubectl)

    if [[ ${#missing[@]} -gt 0 ]]; then
        die "Missing required tools: ${missing[*]}"
    fi

    if [[ ! -f "${REPO_ROOT}/secrets.yaml" ]]; then
        die "secrets.yaml not found at ${REPO_ROOT}/secrets.yaml\n" \
            "    Copy talos/secrets.yaml.template to secrets.yaml and populate it.\n" \
            "    See talos/README.md for instructions."
    fi
}

# --- Generate configs ---
generate_configs() {
    info "Generating configs from templates..."
    bash "${SCRIPT_DIR}/generate-configs.sh"
    echo ""
}

# --- Resolve config file for a node ---
config_for_node() {
    local node="$1"
    if [[ "$node" == "controlplane" ]]; then
        echo "${GENERATED}/controlplane.yaml"
    elif [[ -f "${GENERATED}/worker-${node}.yaml" ]]; then
        echo "${GENERATED}/worker-${node}.yaml"
    else
        echo "${GENERATED}/worker.yaml"
    fi
}

# --- Wait for a node to respond to talosctl ---
wait_for_talos_api() {
    local node="$1"
    local ip; ip="$(node_ip "$node")"
    local timeout="${2:-300}"
    local elapsed=0

    info "Waiting for Talos API on ${node} (${ip})..."
    while ! talosctl version --nodes "$ip" --talosconfig "$TALOSCONFIG" &>/dev/null; do
        sleep 5
        elapsed=$((elapsed + 5))
        if [[ $elapsed -ge $timeout ]]; then
            die "Timed out waiting for Talos API on ${node} (${ip}) after ${timeout}s"
        fi
        printf "."
    done
    echo ""
    info "${node} Talos API is up."
}

# --- Apply config to a single node ---
apply_node() {
    local node="$1"
    local ip; ip="$(node_ip "$node")"
    local config
    config="$(config_for_node "$node")"

    if [[ ! -f "$config" ]]; then
        die "Config not found: ${config}\n    Run generate_configs first."
    fi

    info "Applying config to ${node} (${ip}) using ${config##*/}..."
    talosctl apply-config \
        --nodes "$ip" \
        --file "$config" \
        --insecure
    info "Config applied to ${node}."
}

# --- Bootstrap the control plane (first-time etcd init) ---
bootstrap_controlplane() {
    local ip; ip="$(node_ip controlplane)"

    info "Bootstrapping etcd on control plane (${ip})..."
    info "Waiting for node to be ready for bootstrap..."

    # After apply-config the node reboots into the new config.
    # Wait for the Talos API to come up with proper auth.
    wait_for_talos_api "controlplane" 600

    talosctl bootstrap \
        --nodes "$ip" \
        --talosconfig "$TALOSCONFIG"
    info "Bootstrap initiated."
}

# --- Fetch kubeconfig ---
fetch_kubeconfig() {
    local ip; ip="$(node_ip controlplane)"
    local kubeconfig="${SCRIPT_DIR}/kubeconfig"

    info "Fetching kubeconfig..."
    talosctl kubeconfig "$kubeconfig" \
        --nodes "$ip" \
        --talosconfig "$TALOSCONFIG" \
        --force
    info "Kubeconfig saved to ${kubeconfig}"
    info "(direnv will auto-export KUBECONFIG when you cd into talos/)"
}

# --- Wait for Kubernetes API ---
wait_for_k8s_api() {
    local kubeconfig="${SCRIPT_DIR}/kubeconfig"
    local timeout=300
    local elapsed=0

    info "Waiting for Kubernetes API..."
    while ! kubectl --kubeconfig "$kubeconfig" get nodes &>/dev/null 2>&1; do
        sleep 5
        elapsed=$((elapsed + 5))
        if [[ $elapsed -ge $timeout ]]; then
            die "Timed out waiting for Kubernetes API after ${timeout}s"
        fi
        printf "."
    done
    echo ""
    info "Kubernetes API is up."
}

# --- Show cluster status ---
cluster_status() {
    local kubeconfig="${SCRIPT_DIR}/kubeconfig"

    if [[ ! -f "$kubeconfig" ]]; then
        warn "No kubeconfig found. Run bootstrap first."
        echo ""
        info "Checking Talos API on known nodes..."
        for node in controlplane ; do
            local ip; ip="$(node_ip "$node")"
            if talosctl version --nodes "$ip" --talosconfig "$TALOSCONFIG" &>/dev/null 2>&1; then
                echo -e "  ${GREEN}✓${NC} ${node} (${ip}) — Talos API reachable"
            elif talosctl version --nodes "$ip" --insecure &>/dev/null 2>&1; then
                echo -e "  ${YELLOW}○${NC} ${node} (${ip}) — maintenance mode"
            else
                echo -e "  ${RED}✗${NC} ${node} (${ip}) — unreachable"
            fi
        done
        return
    fi

    info "Kubernetes nodes:"
    kubectl --kubeconfig "$kubeconfig" get nodes -o wide 2>/dev/null || warn "kubectl failed"
    echo ""
    info "Talos node health:"
    for node in controlplane ; do
        local ip; ip="$(node_ip "$node")"
        if talosctl version --nodes "$ip" --talosconfig "$TALOSCONFIG" &>/dev/null 2>&1; then
            echo -e "  ${GREEN}✓${NC} ${node} (${ip})"
        else
            echo -e "  ${RED}✗${NC} ${node} (${ip})"
        fi
    done
}

# --- Full bootstrap ---
full_bootstrap() {
    check_prereqs
    generate_configs

    info "=== Phase 1: Apply control plane config ==="
    apply_node controlplane

    info "=== Phase 2: Bootstrap etcd ==="
    bootstrap_controlplane

    info "=== Phase 3: Fetch kubeconfig ==="
    fetch_kubeconfig

    info "=== Phase 4: Apply worker configs ==="
    for worker in $WORKERS; do
        local ip
        ip="$(node_ip "$worker")"
        # Only apply if node is reachable
        if ping -c 1 -W 2 "$ip" &>/dev/null || \
           talosctl version --nodes "$ip" --insecure &>/dev/null 2>&1; then
            apply_node "$worker"
        else
            warn "Skipping ${worker} (${ip}) — not reachable. Apply later with:"
            warn "  $0 apply ${worker}"
        fi
    done

    info "=== Phase 5: Wait for Kubernetes ==="
    wait_for_k8s_api

    info "=== Phase 6: Cluster status ==="
    cluster_status

    echo ""
    info "Bootstrap complete."
    info "To apply config to a node that was offline:"
    info "  $0 apply <node>"
}

# --- Main ---
case "${1:-}" in
    apply)
        node="${2:?Usage: $0 apply <node>}"
        if ! node_ip "$node" >/dev/null 2>&1; then
            die "Unknown node: ${node}\nValid nodes: ${ALL_NODES}"
        fi
        check_prereqs
        generate_configs
        apply_node "$node"
        ;;
    status)
        check_prereqs
        cluster_status
        ;;
    "")
        full_bootstrap
        ;;
    *)
        echo "Usage: $0 [apply <node> | status]"
        echo ""
        echo "Commands:"
        echo "  (none)         Full cluster bootstrap"
        echo "  apply <node>   Apply config to a single node"
        echo "  status         Show cluster health"
        echo ""
        echo "Nodes: controlplane snap crackle pop"
        exit 1
        ;;
esac
