#!/usr/bin/env bash

# Install git-delta
# https://github.com/dandavison/delta

GIT_DELTA_VERSION=0.19.2
ARCH=$(dpkg --print-architecture)

FILENAME=$(curl -w '%{filename_effective}' -LJO "https://github.com/dandavison/delta/releases/download/${GIT_DELTA_VERSION}/git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb")
dpkg -i $FILENAME
