#!/usr/bin/env bash

# Install OpenAI Codex CLI. Installation script originally copied from
# https://developers.openai.com/codex/cli

set -euo pipefail
# sudo -iu re-exec may omit _CONTAINER_USER, and fallback avoids set -u failure while preserving current user.
CONTAINER_USER="${_CONTAINER_USER:-$(id -un)}"

if [[ $EUID -ne $(id -u "${CONTAINER_USER}") ]]
then
  # The system bwrap command is this feature's stable capability probe.
  echo ">Installing Bubblewrap"
  apt-get update
  apt-get install -y --no-install-recommends bubblewrap
  rm -rf /var/lib/apt/lists/*

  echo ">Copying config to the remote user's home directory"

  # Copy files over while setting ownership and permissions
  rsync -rp \
      --chown=${CONTAINER_USER}:${CONTAINER_USER} \
      --chmod=D755,F644 \
      home/. "/home/${CONTAINER_USER}"

  # Lifecycle hooks must remain executable.
  rsync -rp \
      --chown=${CONTAINER_USER}:${CONTAINER_USER} \
      --chmod=D755,F755 \
      bin "/home/${CONTAINER_USER}"

  exec sudo -iu "${CONTAINER_USER}" "$(realpath "$0")"
fi

echo ">Switched to the container user"

echo ">Installing Codex CLI"

curl -fsSL https://chatgpt.com/codex/install.sh | CODEX_NON_INTERACTIVE=1 sh

echo ">Done installing Codex CLI"
