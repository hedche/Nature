#!/usr/bin/env bash
# Encrypt/decrypt secrets.yaml with a passphrase using age.
#
# secrets.yaml lives outside the repo (see scripts/secrets-path.sh) — this
# script never reads or writes anything under the repo root, including
# temp files.
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
# Encrypting keeps the plaintext secrets.yaml in place. After encrypting,
# the script offers to move the .age file to the iCloud "Administrator ⚙️"
# folder as the off-machine backup — on success the local copy is deleted,
# so there is exactly one copy of the ciphertext. Decrypt reads the iCloud
# copy when there is no local one.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${REPO_ROOT}/scripts/secrets-path.sh"
PLAIN_FILE="$SECRETS_FILE"
ENC_FILE="${PLAIN_FILE}.age"
ICLOUD_BACKUP_DIR="${HOME}/Library/Mobile Documents/com~apple~CloudDocs/Administrator ⚙️"
ICLOUD_ENC_FILE="${ICLOUD_BACKUP_DIR}/secrets.yaml.age"

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
    echo "Encryption keeps the plaintext file and offers to move the .age file"
    echo "off the repo root into iCloud. Decrypt falls back to the iCloud copy."
    exit 1
}

cmd_encrypt() {
    require_age
    [[ -f "$PLAIN_FILE" ]] || die "secrets.yaml not found at ${PLAIN_FILE}"

    local tmp
    tmp="$(mktemp "${SECRETS_DIR}/.secrets.yaml.age.XXXXXX")"
    trap 'rm -f "$tmp"' EXIT

    info "Encrypting secrets.yaml (age will prompt for a passphrase)..."
    if ! age -p -o "$tmp" "$PLAIN_FILE"; then
        die "Encryption failed."
    fi

    chmod 600 "$tmp"
    mv "$tmp" "$ENC_FILE"
    trap - EXIT

    info "Wrote $(basename "$ENC_FILE") ($(wc -c < "$ENC_FILE" | tr -d ' ') bytes). Plaintext kept."

    offer_icloud_backup
}

offer_icloud_backup() {
    # Only offer interactively; skip in non-TTY contexts (CI, pipes).
    [[ -t 0 ]] || { warn_left_in_repo; return 0; }

    if [[ ! -d "$ICLOUD_BACKUP_DIR" ]]; then
        warn "iCloud backup dir not found: ${ICLOUD_BACKUP_DIR} — skipping backup offer."
        warn_left_in_repo
        return 0
    fi

    local reply
    read -r -p "Move secrets.yaml.age to iCloud (Administrator ⚙️)? [y/N] " reply
    case "$reply" in
        [yY]|[yY][eE][sS]) ;;
        *) info "Skipped iCloud backup."; warn_left_in_repo; return 0 ;;
    esac

    # Copy, verify, then delete — never remove the repo copy until the
    # iCloud copy is known-good.
    cp "$ENC_FILE" "${ICLOUD_ENC_FILE}.tmp" \
        || die "Copy to iCloud failed; left $(basename "$ENC_FILE") in the repo root."
    if ! cmp -s "$ENC_FILE" "${ICLOUD_ENC_FILE}.tmp"; then
        rm -f "${ICLOUD_ENC_FILE}.tmp"
        die "iCloud copy did not verify; left $(basename "$ENC_FILE") in the repo root."
    fi
    chmod 600 "${ICLOUD_ENC_FILE}.tmp"
    mv "${ICLOUD_ENC_FILE}.tmp" "$ICLOUD_ENC_FILE"

    rm -f "$ENC_FILE"
    info "Moved to ${ICLOUD_ENC_FILE} — iCloud now holds the only copy."
}

warn_left_in_repo() {
    warn "$(basename "$ENC_FILE") is still at ${ENC_FILE} with no off-machine" \
         "backup. Re-run and accept, or copy it into iCloud yourself."
}

cmd_decrypt() {
    require_age
    local force="$1"

    # The repo root copy is transient; iCloud is where the .age file lives.
    local src
    if [[ -f "$ENC_FILE" ]]; then
        src="$ENC_FILE"
    elif [[ -f "$ICLOUD_ENC_FILE" ]]; then
        src="$ICLOUD_ENC_FILE"
        info "Using the iCloud copy: ${src}"
    else
        die "secrets.yaml.age not found at ${ENC_FILE} or ${ICLOUD_ENC_FILE}"
    fi

    if [[ -f "$PLAIN_FILE" && "$force" != "true" ]]; then
        die "secrets.yaml already exists. Re-run with -f to overwrite it.\n" \
            "    Compare first with: age -d '${src}' | diff ${PLAIN_FILE} -"
    fi

    local tmp
    tmp="$(mktemp "${SECRETS_DIR}/.secrets.yaml.XXXXXX")"
    trap 'rm -f "$tmp"' EXIT

    info "Decrypting secrets.yaml.age (age will prompt for the passphrase)..."
    if ! age -d -o "$tmp" "$src"; then
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
