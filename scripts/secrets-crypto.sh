#!/usr/bin/env bash
# Encrypt/decrypt the root secrets.yaml with a passphrase using age.
#
# age -p derives a 256-bit key from the passphrase with scrypt and encrypts
# with ChaCha20-Poly1305 — post-quantum safe for symmetric, password-based
# encryption (no public-key component; Grover leaves ~128-bit strength).
#
# The passphrase is only ever read from the terminal by age itself — never
# passed on argv or via the environment.
#
# Usage:
#   ./scripts/secrets-crypto.sh -e            Encrypt secrets.yaml -> secrets.yaml.age
#   ./scripts/secrets-crypto.sh -d [-f]       Decrypt secrets.yaml.age -> secrets.yaml
#
# Encrypting keeps the plaintext secrets.yaml in place. Both files are
# gitignored; the .age file exists for local at-rest backup only.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLAIN_FILE="${REPO_ROOT}/secrets.yaml"
ENC_FILE="${REPO_ROOT}/secrets.yaml.age"

# --- Colours ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${GREEN}==>${NC} ${BOLD}$*${NC}"; }
warn()  { echo -e "${YELLOW}==> WARNING:${NC} $*"; }
die()   { echo -e "${RED}==> ERROR:${NC} $*" >&2; exit 1; }

require_age() {
    command -v age &>/dev/null || die "age is required. Install with: brew install age"
}

usage() {
    echo "Usage: $0 -e | -d [-f]"
    echo ""
    echo "  -e          Encrypt secrets.yaml -> secrets.yaml.age (prompts for passphrase)"
    echo "  -d          Decrypt secrets.yaml.age -> secrets.yaml"
    echo "  -f, --force With -d: overwrite an existing secrets.yaml"
    echo ""
    echo "Encryption keeps the plaintext file; both files stay local (gitignored)."
    exit 1
}

cmd_encrypt() {
    require_age
    [[ -f "$PLAIN_FILE" ]] || die "secrets.yaml not found at ${PLAIN_FILE}"

    local tmp
    tmp="$(mktemp "${REPO_ROOT}/.secrets.yaml.age.XXXXXX")"
    trap 'rm -f "$tmp"' EXIT

    info "Encrypting secrets.yaml (age will prompt for a passphrase)..."
    if ! age -p -o "$tmp" "$PLAIN_FILE"; then
        die "Encryption failed."
    fi

    chmod 600 "$tmp"
    mv "$tmp" "$ENC_FILE"
    trap - EXIT

    info "Wrote $(basename "$ENC_FILE") ($(wc -c < "$ENC_FILE" | tr -d ' ') bytes). Plaintext kept."
}

cmd_decrypt() {
    require_age
    local force="$1"
    [[ -f "$ENC_FILE" ]] || die "secrets.yaml.age not found at ${ENC_FILE}"

    if [[ -f "$PLAIN_FILE" && "$force" != "true" ]]; then
        die "secrets.yaml already exists. Re-run with -f to overwrite it.\n" \
            "    Compare first with: age -d ${ENC_FILE} | diff ${PLAIN_FILE} -"
    fi

    local tmp
    tmp="$(mktemp "${REPO_ROOT}/.secrets.yaml.XXXXXX")"
    trap 'rm -f "$tmp"' EXIT

    info "Decrypting secrets.yaml.age (age will prompt for the passphrase)..."
    if ! age -d -o "$tmp" "$ENC_FILE"; then
        die "Decryption failed (wrong passphrase or corrupt file)."
    fi

    chmod 600 "$tmp"
    mv "$tmp" "$PLAIN_FILE"
    trap - EXIT

    info "Wrote secrets.yaml."
}

# --- Main ---
mode=""
force="false"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -e|--encrypt) mode="encrypt"; shift ;;
        -d|--decrypt) mode="decrypt"; shift ;;
        -f|--force)   force="true"; shift ;;
        *)            usage ;;
    esac
done

case "$mode" in
    encrypt) cmd_encrypt ;;
    decrypt) cmd_decrypt "$force" ;;
    *)       usage ;;
esac
