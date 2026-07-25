#!/usr/bin/env bash
# Resolve the location of the real secrets.yaml. Source this; don't run it.
#
#   source "${REPO_ROOT}/scripts/secrets-path.sh"
#   # -> $SECRETS_FILE is now set
#
# secrets.yaml deliberately lives OUTSIDE the repo. Nature is a public
# repo, and a file that is not in the working tree cannot be committed by
# a stray `git add -A`, an editor, or a `git add -f` that overrides
# .gitignore. That structural guarantee is the whole point — please don't
# "simplify" this back to a path under ${REPO_ROOT}.
#
# Override with NATURE_SECRETS_FILE for a one-off run against another file.

SECRETS_DIR="${NATURE_SECRETS_DIR:-${HOME}/.config/nature}"
SECRETS_FILE="${NATURE_SECRETS_FILE:-${SECRETS_DIR}/secrets.yaml}"

# Migration aid: a clone that still has the pre-move file at the repo root
# keeps working, but says so every time. Remove this block once every
# machine is migrated. An explicit NATURE_SECRETS_FILE is never second-
# guessed — if the caller named a file, a missing file is an error for the
# caller to report, not a cue to silently use a different one.
if [[ -z "${NATURE_SECRETS_FILE:-}" && ! -f "$SECRETS_FILE" \
      && -n "${REPO_ROOT:-}" && -f "${REPO_ROOT}/secrets.yaml" ]]; then
    echo "==> WARNING: using legacy ${REPO_ROOT}/secrets.yaml" >&2
    echo "    Move it out of the repo:  mkdir -p '${SECRETS_DIR}' && mv '${REPO_ROOT}/secrets.yaml' '${SECRETS_DIR}/'" >&2
    SECRETS_FILE="${REPO_ROOT}/secrets.yaml"
fi
