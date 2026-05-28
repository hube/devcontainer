#!/usr/bin/env bash

# Install Claude Code. Installation location originally copied from
# https://docs.anthropic.com/en/docs/claude-code/getting-started

if [[ $EUID -ne $(id -u ${_CONTAINER_USER}) ]]
then
  echo ">Copying config to the remote user's home directory"

  # copy files over while setting ownership and permissions
  rsync -rp \
      --chown=${_CONTAINER_USER}:${_CONTAINER_USER} \
      --chmod=D755,F644 \
      config/. /home/${_CONTAINER_USER}

  exec sudo -iu "${_CONTAINER_USER}" "$(realpath $0)"
fi

echo ">Installing Claude Code"

curl -fsSL https://claude.ai/install.sh | bash

echo ">Done installing Claude code"
