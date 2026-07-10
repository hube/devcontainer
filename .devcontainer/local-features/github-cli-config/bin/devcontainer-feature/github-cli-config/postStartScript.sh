#!/usr/bin/env bash
# Stores the runtime token for GitHub CLI processes that do not inherit remoteEnv.
set -uo pipefail

warn() { echo "github-cli-config: $*" >&2; }

if [[ -n "${GH_TOKEN:-}" ]]; then
  selected_token="$GH_TOKEN"
elif [[ -n "${GITHUB_TOKEN:-}" ]]; then
  selected_token="$GITHUB_TOKEN"
else
  warn "no GitHub CLI auth changes are being made because GH_TOKEN and GITHUB_TOKEN are unset or empty."
  exit 0
fi

if ! printf '%s\n' "$selected_token" | env -u GH_TOKEN -u GITHUB_TOKEN gh auth login \
  --hostname github.com \
  --with-token \
  --insecure-storage; then
  warn "gh auth login failed; no further GitHub CLI auth changes are being made."
fi

exit 0
