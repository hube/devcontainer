#!/usr/bin/env bash
# Checks the documented contract for the GitHub CLI configuration feature.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
NOTES="$ROOT/.devcontainer/local-features/github-cli-config/NOTES.md"

require() {
  local pattern="$1"
  local file="$2"
  local content
  content="$(tr "\n" " " < "$file")"
  grep -Fq -- "$pattern" <<< "$content" || {
    printf 'Missing required documentation in %s: %s\n' "$file" "$pattern" >&2
    exit 1
  }
}

require_lines() {
  local pattern="$1"
  local file="$2"
  local content
  content="$(<"$file")"
  [[ "$content" == *"$pattern"* ]] || {
    printf 'Required line sequence is missing in %s: %s\n' "$file" "$pattern" >&2
    printf 'Documentation contract verification cannot continue. Restore the required paragraph separation and rerun this test.\n' >&2
    exit 1
  }
}

require 'extends the official `github-cli` feature' "$NOTES"
require 'does not install or replace the `gh` binary' "$NOTES"
require 'top-level `remoteEnv`' "$NOTES"
require 'not feature options or `containerEnv`' "$NOTES"
require '`GH_TOKEN` takes precedence over `GITHUB_TOKEN`' "$NOTES"
require 'unset or empty' "$NOTES"
require 'Stored GitHub CLI authentication was not updated' "$NOTES"
require "--insecure-storage" "$NOTES"
require '`~/.config/gh/hosts.yml`' "$NOTES"
require '`github-cli-config-${devcontainerId}`' "$NOTES"
require 'volume is deleted' "$NOTES"
require 'expires, is revoked, or loses required access' "$NOTES"
require 'plaintext' "$NOTES"
require 'Secret Service' "$NOTES"
require 'keyring session' "$NOTES"
require 'unsets `GH_TOKEN` and `GITHUB_TOKEN` for `gh auth login`' "$NOTES"
require 'does not remove, log out, switch, delete, or overwrite unrelated stored accounts' "$NOTES"
require "may create or update the account associated with the selected token" "$NOTES"
require 'Classic personal access tokens are preferred' "$NOTES"
require '`repo`, `read:org`, and `gist`' "$NOTES"
require "Fine-grained tokens" "$NOTES"
require 'does not run `gh auth setup-git`' "$NOTES"
require 'SSH agent forwarding' "$NOTES"
require 'minimum permissions' "$NOTES"
require '`gh auth logout --hostname github.com`' "$NOTES"
require '`docker volume rm github-cli-config-<devcontainerId>`' "$NOTES"
require '.devcontainer/local-features/github-cli-config/NOTES.md' "$ROOT/README.md"
require_lines $'restarting the container.\n\nWhen a token is supplied' "$NOTES"
