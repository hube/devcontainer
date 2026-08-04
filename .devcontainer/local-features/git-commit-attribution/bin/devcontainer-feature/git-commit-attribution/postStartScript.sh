#!/usr/bin/env bash
# Warns about a missing trailer contract and about repositories whose local
# core.hooksPath shadows the gate. Never fails container start.
set -uo pipefail

SPEC="${GCA_SPEC_PATH:-/etc/devcontainer/feature/git-commit-attribution/trailer-contract}"
SCAN_ROOT="${GCA_SCAN_ROOT:-/workspaces}"

if [[ ! -f "$SPEC" ]]; then
  echo "git-commit-attribution: no trailer contract at $SPEC." >&2
  echo "Every commit in this container will be rejected until it exists (the gate fails closed); git commit --no-verify bypasses one commit." >&2
  echo "Remedy: declare the bind mount in devcontainer.json — \${localEnv:HOME}/.claude/git-commit-attribution.conf -> $SPEC — and ensure the host file exists as part of a hube/claude-home checkout at ~/.claude. If Docker created a directory at the host path, remove it and pull claude-home." >&2
fi

if [[ -d "$SCAN_ROOT" ]]; then
  for repo in "$SCAN_ROOT"/*/; do
    [[ -d "$repo" ]] || continue
    if git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      local_path="$(git -C "$repo" config --local --get core.hooksPath 2>/dev/null || true)"
      if [[ -n "$local_path" ]]; then
        echo "git-commit-attribution: $repo sets core.hooksPath=$local_path locally; the gate is silently bypassed there." >&2
      fi
    fi
  done
fi

exit 0
