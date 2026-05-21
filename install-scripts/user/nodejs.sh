#!/usr/bin/env bash

### This script installs NodeJS. Some commands originally copied from
### https://nodejs.org/en/download/current

# Prerequisite for running Node. Ubuntu doesn't include libatomic
# https://github.com/nodejs/node/issues/60790
apt install libatomic1

# Download and install nvm:
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh | bash

# in lieu of restarting the shell
\. "$HOME/.nvm/nvm.sh"

# Download and install Node.js:
nvm install --lts

# Verify the Node.js version:
node -v

# Install Corepack:
npm install -g corepack

# Download and install Yarn:
corepack enable yarn

# Verify Yarn version:
yarn -v
