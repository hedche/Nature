#!/usr/bin/env bash
# Bootstrap the cereal Talos Kubernetes cluster.
# Idempotent — safe to re-run on an already-running cluster.
#
# Usage:
#   ./talos/bootstrap.sh                  # Full cluster bootstrap
#   ./talos/bootstrap.sh apply <node>     # Apply config to a single node
#   ./talos/bootstrap.sh apply-labels     # Apply k8s labels to all workers
#   ./talos/bootstrap.sh apply-labels <n> # Apply k8s labels to a single node
#   ./talos/bootstrap.sh bootstrap-flux   # Bootstrap Flux CD GitOps
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

# --- Check if a node is running with authenticated Talos API ---
node_is_authenticated() {
    local ip="$1"
    talosctl version --nodes "$ip" --talosconfig "$TALOSCONFIG" &>/dev/null 2>&1
}

# --- Apply config to a single node ---
# Tries authenticated mode first (running cluster), falls back to --insecure
# (maintenance mode / first boot).
apply_node() {
    local node="$1"
    local ip; ip="$(node_ip "$node")"
    local config
    config="$(config_for_node "$node")"

    if [[ ! -f "$config" ]]; then
        die "Config not found: ${config}\n    Run generate_configs first."
    fi

    info "Applying config to ${node} (${ip}) using ${config##*/}..."
    if node_is_authenticated "$ip"; then
        talosctl apply-config \
            --nodes "$ip" \
            --file "$config" \
            --talosconfig "$TALOSCONFIG"
    else
        talosctl apply-config \
            --nodes "$ip" \
            --file "$config" \
            --insecure
    fi
    info "Config applied to ${node}."
}

# --- Check if etcd is already bootstrapped ---
etcd_is_running() {
    local ip="$1"
    talosctl service etcd --nodes "$ip" --talosconfig "$TALOSCONFIG" 2>/dev/null \
        | grep -q "Running" 2>/dev/null
}

# --- Bootstrap the control plane (first-time etcd init) ---
# Idempotent: skips if etcd is already running.
bootstrap_controlplane() {
    local ip; ip="$(node_ip controlplane)"

    # After apply-config the node reboots into the new config.
    # Wait for the Talos API to come up with proper auth.
    wait_for_talos_api "controlplane" 600

    if etcd_is_running "$ip"; then
        info "etcd already running on ${ip} — skipping bootstrap."
        return
    fi

    info "Bootstrapping etcd on control plane (${ip})..."
    talosctl bootstrap \
        --nodes "$ip" \
        --talosconfig "$TALOSCONFIG"
    info "Bootstrap initiated."
}

# --- Fetch kubeconfig ---
# Skips if a working kubeconfig already exists.
fetch_kubeconfig() {
    local ip; ip="$(node_ip controlplane)"
    local kubeconfig="${SCRIPT_DIR}/kubeconfig"

    if [[ -f "$kubeconfig" ]] && kubectl --kubeconfig "$kubeconfig" get nodes &>/dev/null 2>&1; then
        info "Kubeconfig already exists and works — skipping fetch."
        return
    fi

    info "Fetching kubeconfig..."
    talosctl kubeconfig "$kubeconfig" \
        --nodes "$ip" \
        --talosconfig "$TALOSCONFIG" \
        --force
    # Replace DNS endpoint with IP if the DNS name doesn't resolve yet.
    # This prevents the kubeconfig from becoming unusable before DNS is configured.
    local endpoint
    endpoint="$(grep -o 'https://[^:]*:6443' "$kubeconfig" | head -1)"
    local hostname="${endpoint#https://}"
    hostname="${hostname%:6443}"
    if [[ "$hostname" != "$ip" ]] && ! host "$hostname" &>/dev/null 2>&1; then
        warn "DNS for ${hostname} not resolvable — using IP ${ip} in kubeconfig."
        sed -i '' "s|${endpoint}|https://${ip}:6443|" "$kubeconfig" 2>/dev/null \
            || sed -i "s|${endpoint}|https://${ip}:6443|" "$kubeconfig"
    fi
    info "Kubeconfig saved to ${kubeconfig}"
    info "(direnv will auto-export KUBECONFIG when you cd into talos/)"
}

# --- Apply Kubernetes labels that kubelets cannot self-assign ---
# NodeRestriction admission prevents kubelets from setting node-role.kubernetes.io/*
# labels, so we apply them from an admin kubeconfig after the API is up.
apply_node_labels() {
    local kubeconfig="${SCRIPT_DIR}/kubeconfig"
    local node="${1:-}"

    if [[ ! -f "$kubeconfig" ]]; then
        warn "No kubeconfig found — skipping node label application."
        return
    fi

    if [[ -n "$node" ]]; then
        # Label a single node
        local nodes_to_label="$node"
    else
        # Label all workers
        local nodes_to_label="$WORKERS"
    fi

    for n in $nodes_to_label; do
        # Only label worker nodes
        local is_worker=false
        for w in $WORKERS; do
            [[ "$w" == "$n" ]] && is_worker=true
        done
        if ! $is_worker; then
            continue
        fi

        if kubectl --kubeconfig "$kubeconfig" get node "$n" &>/dev/null 2>&1; then
            kubectl --kubeconfig "$kubeconfig" label node "$n" \
                node-role.kubernetes.io/worker= --overwrite &>/dev/null
            info "Labeled ${n} as worker."
        else
            warn "Node ${n} not yet registered in Kubernetes — label later with:"
            warn "  $0 apply-labels ${n}"
        fi
    done
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

# --- Bootstrap Flux CD ---
bootstrap_flux() {
    if ! command -v flux &>/dev/null; then
        die "flux CLI is required.\n    Install with: brew install fluxcd/tap/flux\n    Or: curl -s https://fluxcd.io/install.sh | bash"
    fi

    local kubeconfig="${SCRIPT_DIR}/kubeconfig"
    if [[ ! -f "$kubeconfig" ]]; then
        die "No kubeconfig found at ${kubeconfig}.\n    Run the full bootstrap or fetch_kubeconfig first."
    fi

    # Read the GitHub PAT from the secrets pipeline
    local token
    token="$(yq eval '.kubernetes.secrets[] | select(.name == "flux-system") | .data.password' "${REPO_ROOT}/secrets.yaml")"
    if [[ -z "$token" || "$token" == "null" ]]; then
        die "Flux secret not found in secrets.yaml.\n" \
            "    Create it with:\n" \
            "    ./scripts/secrets.sh create flux-system -n flux-system --type Opaque --from-literal username=git --from-literal password=YOUR_GITHUB_PAT"
    fi

    info "Bootstrapping Flux CD..."
    KUBECONFIG="$kubeconfig" GITHUB_TOKEN="$token" flux bootstrap github \
        --components-extra=image-reflector-controller,image-automation-controller \
        --owner=hedche \
        --repository=Nature \
        --path=kubernetes/flux \
        --personal \
        --token-auth

    info "Running Flux pre-flight checks..."
    KUBECONFIG="$kubeconfig" flux check
    info "Flux CD bootstrapped successfully."
}

# --- Push Kubernetes secrets ---
push_secrets() {
    local count
    count="$(yq eval '.kubernetes.secrets | length // 0' "${REPO_ROOT}/secrets.yaml")"
    if [[ "$count" -eq 0 ]]; then
        info "No Kubernetes secrets defined in secrets.yaml — skipping."
        return
    fi
    info "Pushing ${count} Kubernetes secret(s)..."
    bash "${REPO_ROOT}/scripts/secrets.sh" push
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

    info "=== Phase 6: Apply node labels ==="
    apply_node_labels

    info "=== Phase 7: Push Kubernetes secrets ==="
    push_secrets

    info "=== Phase 8: Bootstrap Flux CD ==="
    bootstrap_flux

    info "=== Phase 9: Cluster status ==="
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
        apply_node_labels "$node"
        ;;
    apply-labels)
        node="${2:-}"
        if [[ -n "$node" ]] && ! node_ip "$node" >/dev/null 2>&1; then
            die "Unknown node: ${node}\nValid nodes: ${ALL_NODES}"
        fi
        check_prereqs
        apply_node_labels "$node"
        ;;
    push-secrets)
        check_prereqs
        push_secrets
        ;;
    bootstrap-flux)
        check_prereqs
        bootstrap_flux
        ;;
    status)
        check_prereqs
        cluster_status
        ;;
    "")
        full_bootstrap
        ;;
    *)
        echo "Usage: $0 [apply <node> | apply-labels [node] | push-secrets | bootstrap-flux | status]"
        echo ""
        echo "Commands:"
        echo "  (none)             Full cluster bootstrap"
        echo "  apply <node>       Apply config to a single node (+ labels)"
        echo "  apply-labels       Apply k8s labels to all worker nodes"
        echo "  apply-labels <n>   Apply k8s labels to a single node"
        echo "  push-secrets       Push Kubernetes secrets to cluster"
        echo "  bootstrap-flux     Bootstrap Flux CD for GitOps"
        echo "  status             Show cluster health"
        echo ""
        echo "Nodes: controlplane snap crackle pop"
        exit 1
        ;;
esac
