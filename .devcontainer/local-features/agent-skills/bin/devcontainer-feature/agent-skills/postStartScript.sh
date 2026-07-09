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

# shellcheck source=/dev/null
source "$ENV_FILE"

repo="${AGENT_SKILLS_REPO:-}"
clone_dir="${AGENT_SKILLS_CLONE_DIR:-}"

if [[ -z "$repo" || -z "$clone_dir" ]]; then
  bail "the options file $ENV_FILE does not define AGENT_SKILLS_REPO and AGENT_SKILLS_CLONE_DIR, so the bootstrap cannot run. hube-agent skills will not load. Rebuild the container to reinstall the Feature."
fi

if [[ -e "$clone_dir" && ! -d "$clone_dir" ]]; then
  bail "$clone_dir exists and is not a directory, so the clone cannot be created. hube-agent skills will not load. Remove it, then restart the container."
fi

if [[ -d "$clone_dir/.git" ]]; then
  git -C "$clone_dir" fetch --quiet \
    || warn "git fetch failed in $clone_dir, so its remote refs are stale. Skills still load from the existing clone."
elif [[ -d "$clone_dir" && -n "$(ls -A "$clone_dir" 2>/dev/null)" ]]; then
  bail "$clone_dir is not empty and is not a git repository, so it will not be cloned over. hube-agent skills will not load. Move it aside, then restart the container."
else
  ssh-add -l >/dev/null 2>&1
  case $? in
    0) ;;
    1) bail "the SSH agent holds no identities, so $repo cannot be cloned. hube-agent skills will not load. Run \`ssh-add\` on the host, then restart the container." ;;
    *) bail "the SSH agent is unreachable at SSH_AUTH_SOCK=${SSH_AUTH_SOCK:-unset}, so $repo cannot be cloned. hube-agent skills will not load. Check SSH agent forwarding on the host, then restart the container." ;;
  esac

  git clone --quiet "$repo" "$clone_dir" \
    || bail "cloning $repo into $clone_dir failed, so no skills are installed. hube-agent skills will not load. Check network access and repository permissions, then restart the container."
fi

if [[ ! -f "$clone_dir/setup.sh" ]]; then
  bail "$clone_dir/setup.sh is missing, so the installer cannot run. hube-agent skills will not load. Check that $repo still ships setup.sh."
fi

bash "$clone_dir/setup.sh" \
  || warn "$clone_dir/setup.sh failed, so hube-agent skills may not load. Re-run it by hand to see the error."

exit 0
