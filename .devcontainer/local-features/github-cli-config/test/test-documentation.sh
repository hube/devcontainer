#!/usr/bin/env bash
# Checks the documented contract for the GitHub CLI configuration Feature.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
README="$ROOT/.devcontainer/local-features/github-cli-config/README.md"

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

require 'extends the official `github-cli` Feature' "$README"
require 'does not install or replace the `gh` binary' "$README"
require 'top-level `remoteEnv`' "$README"
require 'not Feature options or `containerEnv`' "$README"
require '`GH_TOKEN` takes precedence over `GITHUB_TOKEN`' "$README"
require 'unset or empty' "$README"
require 'no GitHub CLI auth changes' "$README"
require "--insecure-storage" "$README"
require '`~/.config/gh/hosts.yml`' "$README"
require '`github-cli-config-${devcontainerId}`' "$README"
require 'volume is deleted' "$README"
require 'expires, is revoked, or loses required access' "$README"
require 'plaintext' "$README"
require 'Secret Service' "$README"
require 'keyring session' "$README"
require 'unsets `GH_TOKEN` and `GITHUB_TOKEN` for `gh auth login`' "$README"
require 'does not remove, log out, switch, delete, or overwrite unrelated stored accounts' "$README"
require "may create or update the account associated with the selected token" "$README"
require 'classic personal access tokens' "$README"
require "Fine-grained tokens" "$README"
require '.devcontainer/local-features/github-cli-config/README.md' "$ROOT/README.md"
