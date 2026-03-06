#!/usr/bin/env bash

### This script installs NodeJS. Instructions originally copied from
### https://nodejs.org/en/download/current

# Prerequisite for running Node. Ubuntu doesn't include libatomic
# https://github.com/nodejs/node/issues/60790
apt install libatomic1

# Download and install nvm:
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh | bash

# in lieu of restarting the shell
\. "$HOME/.nvm/nvm.sh"

# Download and install Node.js:
nvm install 25

# Verify the Node.js version:
node -v # Should print "v25.8.0".

# Install Corepack:
npm install -g corepack

# Download and install Yarn:
corepack enable yarn

# Verify Yarn version:
yarn -v
