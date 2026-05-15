#!/usr/bin/env bash
# Encrypt secrets.yaml with age and store in the repo.
#
# Usage:
#   ./scripts/backup-secrets.sh                     # uses AGE_RECIPIENT from env or prompts
#   AGE_RECIPIENT=age1xyz... ./scripts/backup-secrets.sh
#
# The encrypted file (secrets.yaml.age) is safe to commit to git.
# The age private key should be stored in a password manager or safe location.
#
# First-time setup:
#   brew install age
#   age-keygen -o ~/.config/age/nature.key
#   # Note the public key (age1...) printed to stderr
#   # Store the private key file safely — it's your only decryption key

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SECRETS_FILE="${REPO_ROOT}/secrets.yaml"
ENCRYPTED_FILE="${REPO_ROOT}/secrets.yaml.age"

RED='\033[0;31m'
GREEN='\033[0;32m'
BOLD='\033[1m'
NC='\033[0m'

info() { echo -e "${GREEN}==>${NC} ${BOLD}$*${NC}"; }
die()  { echo -e "${RED}==> ERROR:${NC} $*" >&2; exit 1; }

# Check age is installed
command -v age &>/dev/null || die "age is not installed. Install with: brew install age"

# Check secrets.yaml exists
[[ -f "$SECRETS_FILE" ]] || die "secrets.yaml not found at ${SECRETS_FILE}"

# Resolve the age recipient (public key)
if [[ -z "${AGE_RECIPIENT:-}" ]]; then
    # Try to extract from existing .age file's header
    if [[ -f "$ENCRYPTED_FILE" ]]; then
        info "No AGE_RECIPIENT set. Re-encrypting with same key."
        info "To use a different key, set AGE_RECIPIENT=age1..."
    fi

    # Try to read from the default key file
    AGE_KEY_FILE="${AGE_KEY_FILE:-${HOME}/.config/age/nature.key}"
    if [[ -f "$AGE_KEY_FILE" ]]; then
        AGE_RECIPIENT="$(grep -o 'age1[a-z0-9]*' "$AGE_KEY_FILE" | head -1)" || true
    fi

    if [[ -z "${AGE_RECIPIENT:-}" ]]; then
        echo "Enter your age public key (age1...):"
        read -r AGE_RECIPIENT
    fi
fi

[[ "$AGE_RECIPIENT" == age1* ]] || die "Invalid age public key: ${AGE_RECIPIENT}"

# Encrypt
info "Encrypting secrets.yaml..."
age -r "$AGE_RECIPIENT" -o "$ENCRYPTED_FILE" "$SECRETS_FILE"

info "Encrypted to secrets.yaml.age"
info "This file is safe to commit to git."
echo ""
echo "  git add secrets.yaml.age"
echo "  git commit -m 'chore: update encrypted secrets backup'"
