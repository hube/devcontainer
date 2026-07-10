#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${_CONTAINER_USER:-}" ]] || ! id "${_CONTAINER_USER}" >/dev/null 2>&1; then
  echo "github-cli-config: container user '${_CONTAINER_USER:-}' does not exist" >&2
  exit 1
fi

user_home="/home/${_CONTAINER_USER}"

# Seed the image with user-owned mount metadata before Docker initializes the
# volume. Name each directory level explicitly: install -d applies ownership
# only to the directories it is told to create, and a root-owned ~/.config
# would block the user from writing other tool configuration.
install -d -o "${_CONTAINER_USER}" -g "${_CONTAINER_USER}" -m 0755 "$user_home/.config" "$user_home/.config/gh"

rsync -rp \
  --chown="${_CONTAINER_USER}:${_CONTAINER_USER}" \
  --chmod=D755,F755 \
  bin "${user_home}"
