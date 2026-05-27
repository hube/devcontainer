#!/usr/bin/env bash

# Entrypoint for running post-container creation scripts. These scripts run as
# the container user

echo ">Running postCreate scripts"

install-scripts/copy_dotfiles.sh
install-scripts/claude.sh

echo ">Done running postCreate scripts"
