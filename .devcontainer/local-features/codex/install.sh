#!/usr/bin/env bash

# Install OpenAI Codex CLI. Installation script originally copied from
# https://developers.openai.com/codex/cli

if [[ $EUID -ne $(id -u ${_CONTAINER_USER}) ]]
then
  echo ">Copying config to the remote user's home directory"

  # Copy files over while setting ownership and permissions
  rsync -rp \
      --chown=${_CONTAINER_USER}:${_CONTAINER_USER} \
      --chmod=D755,F644 \
      home/. /home/${_CONTAINER_USER}

  exec sudo -iu "${_CONTAINER_USER}" "$(realpath $0)"
fi

echo ">Switched to the container user"

echo ">Installing Codex CLI"

curl -fsSL https://chatgpt.com/codex/install.sh | CODEX_NON_INTERACTIVE=1 sh

echo ">Done installing Codex CLI"
