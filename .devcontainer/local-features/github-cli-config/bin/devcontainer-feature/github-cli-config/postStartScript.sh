#!/usr/bin/env bash
# Stores the runtime token for GitHub CLI processes that do not inherit remoteEnv.
set -uo pipefail

warn() { echo "github-cli-config: $*" >&2; }

if [[ -n "${GH_TOKEN:-}" ]]; then
  selected_token="$GH_TOKEN"
elif [[ -n "${GITHUB_TOKEN:-}" ]]; then
  selected_token="$GITHUB_TOKEN"
else
  warn "GitHub CLI bootstrap token is unavailable: GH_TOKEN and GITHUB_TOKEN are unset or empty. Stored GitHub CLI authentication was not updated. Set GH_TOKEN or GITHUB_TOKEN on the host, then restart the container."
  exit 0
fi

gh_output="$(
  printf '%s\n' "$selected_token" | env -u GH_TOKEN -u GITHUB_TOKEN gh auth login \
    --hostname github.com \
    --with-token \
    --insecure-storage 2>&1
)"
gh_status=$?

if ((gh_status != 0)); then
  gh_error="${gh_output//$'\n'/; }"
  [[ -n "$gh_error" ]] || gh_error="gh auth login exited with status $gh_status without diagnostic output"
  if ((gh_status == 127)); then
    warn "GitHub CLI is unavailable: $gh_error. Stored GitHub CLI authentication was not updated. Ensure the github-cli feature is installed, then rebuild the container."
  else
    warn "GitHub CLI authentication failed: $gh_error. Stored GitHub CLI authentication was not updated. Verify the token is valid and includes repo, read:org, and gist; then restart the container."
  fi
fi

exit 0
