#!/usr/bin/env bash
# Warns about a missing trailer contract and about repositories whose local
# core.hooksPath shadows the gate. Never fails container start.
set -uo pipefail

SPEC="${GCA_SPEC_PATH:-/etc/devcontainer/feature/git-commit-attribution/trailer-contract}"
SCAN_ROOT="${GCA_SCAN_ROOT:-/workspaces}"
# Test seam only; defaults to the installed gate's hooks directory (the value
# every repo's EFFECTIVE core.hooksPath should resolve to via /etc/gitconfig
# in a rebuilt container).
GCA_HOOKS_PATH="${GCA_HOOKS_PATH:-/usr/local/share/git-commit-attribution/hooks}"

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
    local effective_path
    # The EFFECTIVE value (no --local) is what git actually uses to dispatch
    # hooks, so this catches every scope that can shadow the gate --
    # worktree, local, and global -- not only --local. A worktree-scoped
    # override (extensions.worktreeConfig=true plus `git config --worktree
    # core.hooksPath ...`) is invisible to `--local --get` (rc=1) but IS the
    # effective value, which is what missed it before.
    effective_path="$(git -C "$candidate" config --get core.hooksPath 2>/dev/null || true)"
    if [[ -n "$effective_path" && "$effective_path" != "$GCA_HOOKS_PATH" ]]; then
      echo "git-commit-attribution: $candidate sets core.hooksPath=$effective_path (effective, from worktree/local/global config); the gate is silently bypassed there." >&2
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
