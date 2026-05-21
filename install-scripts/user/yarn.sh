#!/usr/bin/env bash

# Needed because NPM isn't in the PATH
\. "$HOME/.nvm/nvm.sh"

# Install Corepack:
npm install -g corepack

# Download and install Yarn:
corepack enable yarn

# Verify Yarn version:
yarn -v
