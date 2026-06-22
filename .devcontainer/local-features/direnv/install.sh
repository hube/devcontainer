#!/usr/bin/env bash

if [[ $EUID -ne $(id -u ${_CONTAINER_USER}) ]]
then
  echo ">Installing direnv"

  apt update
  apt install -y direnv

  exec sudo -iu "${_CONTAINER_USER}" "$(realpath $0)" $CLAUDE_CONFIG_DIR
fi

# Create config dir for direnv
mkdir -p ~/.local/share/direnv

echo ">Adding direnv plugin to .zshrc"

PLUGIN_NAME="direnv"
if grep -q "plugins=(" ~/.zshrc; then
  sed -i "s/plugins=(\(.*\))/plugins=(\1 $PLUGIN_NAME)/" ~/.zshrc
else
  echo "plugins=($PLUGIN_NAME)" >> ~/.zshrc
fi
