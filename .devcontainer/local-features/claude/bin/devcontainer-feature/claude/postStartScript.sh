#!/usr/bin/env bash
# Warns when the shared agent instructions mount is absent. Never fails
# container start: missing shared instructions degrade guidance, they do not
# make the container unusable.
set -uo pipefail

instructions="$HOME/.agents/instructions"

if [[ -d "$instructions" ]]; then
  exit 0
fi

# A file or symlink at the target is a different failure from nothing at all:
# it must be removed before a bind mount can land there.
if [[ -e "$instructions" || -L "$instructions" ]]; then
  printf '%s\n' \
    "claude: $instructions exists but is not a directory, so the shared agent instructions cannot be read. Claude Code cannot resolve the ~/.agents/instructions pointer in CLAUDE.md, so the rigor-levels reference and the reviewer dispatch blocks are unavailable. Remove it, declare the consumer mount documented in hube/devcontainer's .devcontainer/local-features/claude/NOTES.md, then restart the container. If ~/.claude/instructions on the host is itself a file rather than a directory, replace it with a directory on the host, because declaring the mount cannot fix a file at the mount's source." >&2
  exit 0
fi

printf '%s\n' \
  "claude: $instructions is absent, so the shared agent instructions are not mounted. Claude Code cannot resolve the ~/.agents/instructions pointer in CLAUDE.md, so the rigor-levels reference and the reviewer dispatch blocks are unavailable. Add the consumer mount documented in hube/devcontainer's .devcontainer/local-features/claude/NOTES.md to devcontainer.json, ensure ~/.claude/instructions exists on the host, then restart the container." >&2

exit 0
