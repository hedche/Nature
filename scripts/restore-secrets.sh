#!/usr/bin/env bash
# Decrypt secrets.yaml.age back to secrets.yaml.
#
# Usage:
#   ./scripts/restore-secrets.sh                              # uses default key
#   AGE_KEY_FILE=~/.config/age/nature.key ./scripts/restore-secrets.sh
#
# Prerequisites:
#   - age (brew install age)
#   - Your age private key file (~/.config/age/nature.key by default)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SECRETS_FILE="${REPO_ROOT}/secrets.yaml"
ENCRYPTED_FILE="${REPO_ROOT}/secrets.yaml.age"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
NC='\033[0m'

info() { echo -e "${GREEN}==>${NC} ${BOLD}$*${NC}"; }
warn() { echo -e "${YELLOW}==> WARNING:${NC} $*"; }
die()  { echo -e "${RED}==> ERROR:${NC} $*" >&2; exit 1; }

# Check age is installed
command -v age &>/dev/null || die "age is not installed. Install with: brew install age"

# Check encrypted file exists
[[ -f "$ENCRYPTED_FILE" ]] || die "secrets.yaml.age not found at ${ENCRYPTED_FILE}\n    Run scripts/backup-secrets.sh first."

# Resolve key file
AGE_KEY_FILE="${AGE_KEY_FILE:-${HOME}/.config/age/nature.key}"

if [[ ! -f "$AGE_KEY_FILE" ]]; then
    die "Age key file not found: ${AGE_KEY_FILE}\n" \
        "    Set AGE_KEY_FILE to your private key location, or generate one:\n" \
        "    age-keygen -o ~/.config/age/nature.key"
fi

# Safety check — don't overwrite without asking
if [[ -f "$SECRETS_FILE" ]]; then
    warn "secrets.yaml already exists."
    echo -n "Overwrite? [y/N] "
    read -r confirm
    if [[ "$confirm" != [yY] ]]; then
        info "Aborted."
        exit 0
    fi
fi

# Decrypt
info "Decrypting secrets.yaml.age..."
age -d -i "$AGE_KEY_FILE" -o "$SECRETS_FILE" "$ENCRYPTED_FILE"

# Set restrictive permissions
chmod 600 "$SECRETS_FILE"

info "Restored secrets.yaml (permissions: 600)"
info "You can now generate configs: ./talos/generate-configs.sh"
