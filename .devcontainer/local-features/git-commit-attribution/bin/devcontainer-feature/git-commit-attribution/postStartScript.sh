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

# Reports on $1 if it is a git repository; returns 0 (found — caller must not
# descend into it further) or 1 (not a repository — caller may look one level
# deeper). Bounded to two levels below SCAN_ROOT: this container's checkouts
# sit at /workspaces/<parent>/<repo>, one level deeper than a plain
# /workspaces/<repo> layout, and either shape is live simultaneously (see
# NOTES.md). Descent stops the moment a repo is found so a repo's own
# subdirectories are never re-scanned as separate candidates.
scan_candidate() {
  local candidate="$1"
  if git -C "$candidate" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    local local_path
    local_path="$(git -C "$candidate" config --local --get core.hooksPath 2>/dev/null || true)"
    if [[ -n "$local_path" ]]; then
      echo "git-commit-attribution: $candidate sets core.hooksPath=$local_path locally; the gate is silently bypassed there." >&2
    fi
    return 0
  fi
  return 1
}

if [[ -d "$SCAN_ROOT" ]]; then
  for entry in "$SCAN_ROOT"/*/; do
    [[ -d "$entry" ]] || continue
    entry="${entry%/}"
    scan_candidate "$entry" && continue
    for child in "$entry"/*/; do
      [[ -d "$child" ]] || continue
      child="${child%/}"
      scan_candidate "$child" || true
    done
  done
fi

exit 0
