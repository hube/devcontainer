#!/usr/bin/env bash
# Clones agent-skills if absent, refreshes remote refs if present, then runs the
# repo's own idempotent installer. Never fails container start: an unusable SSH
# agent or an unreachable remote must not stop the container from coming up.
set -uo pipefail

ENV_FILE="${AGENT_SKILLS_ENV_FILE:-$HOME/.config/devcontainer-feature/agent-skills.env}"

warn() { echo "agent-skills: $*" >&2; }

# The ~/.claude volume outlives rebuilds, so the skills symlink can survive a
# clone that did not. Say so rather than deleting what the user owns.
bail() {
  warn "$1"
  local link="$HOME/.claude/skills/hube-agent"
  if [[ -L "$link" && ! -e "$link" ]]; then
    warn "$link is a dangling symlink left by an earlier container, so Claude Code will not load hube-agent skills."
  fi
  exit 0
}

if [[ ! -r "$ENV_FILE" ]]; then
  bail "the options file $ENV_FILE is missing or unreadable, so the bootstrap cannot run. hube-agent skills will not load. Rebuild the container to reinstall the Feature."
fi

source "$ENV_FILE"

repo="${AGENT_SKILLS_REPO:-}"
clone_dir="${AGENT_SKILLS_CLONE_DIR:-}"

if [[ -z "$repo" || -z "$clone_dir" ]]; then
  bail "the options file $ENV_FILE must define both AGENT_SKILLS_REPO and AGENT_SKILLS_CLONE_DIR, but AGENT_SKILLS_REPO='$repo' and AGENT_SKILLS_CLONE_DIR='$clone_dir', so the bootstrap cannot run. hube-agent skills will not load. Set both in $ENV_FILE, or rebuild the container to reinstall the feature."
fi

if [[ -e "$clone_dir" && ! -d "$clone_dir" ]]; then
  bail "$clone_dir exists and is not a directory, so the clone cannot be created. hube-agent skills will not load. Remove it, then restart the container."
fi

if [[ -d "$clone_dir/.git" ]]; then
  if ! output="$(git -C "$clone_dir" fetch --quiet 2>&1)"; then
    warn "git fetch failed in $clone_dir, so its remote refs are stale. Skills still load from the existing clone. git said: ${output:-no output}"
  fi
elif [[ -d "$clone_dir" && -n "$(ls -A "$clone_dir" 2>/dev/null)" ]]; then
  bail "$clone_dir is not empty and is not a git repository, so it will not be cloned over. hube-agent skills will not load. Move it aside, then restart the container."
else
  ssh-add -l >/dev/null 2>&1
  case $? in
    0) ;;
    1) bail "the SSH agent holds no identities, so $repo cannot be cloned. hube-agent skills will not load. Run \`ssh-add\` on the host, then restart the container." ;;
    *) bail "the SSH agent is unreachable at SSH_AUTH_SOCK=${SSH_AUTH_SOCK:-unset}, so $repo cannot be cloned. hube-agent skills will not load. Check SSH agent forwarding on the host, then restart the container." ;;
  esac

  if ! output="$(git clone --quiet "$repo" "$clone_dir" 2>&1)"; then
    bail "cloning $repo into $clone_dir failed, so no skills are installed. hube-agent skills will not load. Check network access and repository permissions, then restart the container. git said: ${output:-no output}"
  fi
fi

if [[ ! -f "$clone_dir/setup.sh" ]]; then
  bail "$clone_dir/setup.sh is missing, so the installer cannot run. hube-agent skills will not load. Check that $repo still ships setup.sh."
fi

# Docker creates a nested bind mount's target directory inside the parent volume
# owned by root. ~/.claude/skills was such a target until the mount was removed,
# and the ~/.claude volume outlives rebuilds, so the root-owned directory is
# still there in any volume created before then. setup.sh's `mkdir -p` succeeds
# against it and its `ln` then fails. Removing it needs no privilege, because
# ~/.claude belongs to us; setup.sh recreates it.
skills_dir="$HOME/.claude/skills"
if [[ -d "$skills_dir" && ! -w "$skills_dir" ]]; then
  if rmdir "$skills_dir" 2>/dev/null; then
    warn "$skills_dir was an empty directory left behind by a bind mount that no longer exists, and it was not writable. Removed it so setup.sh can recreate it."
  else
    bail "$skills_dir is not writable and is not empty, so setup.sh cannot create the skills symlink. hube-agent skills will not load. Run: sudo chown -R $(id -un) $skills_dir"
  fi
fi

# Captured so a failure and its cause arrive as one message. Discards setup.sh's
# success chatter, which nobody reads in container start logs.
if ! output="$(bash "$clone_dir/setup.sh" 2>&1)"; then
  warn "$clone_dir/setup.sh failed, so hube-agent skills may not load. setup.sh said: ${output:-no output}"
fi

exit 0
