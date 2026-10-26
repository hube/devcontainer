#!/usr/bin/env bash
set -euo pipefail
# Bootstrap: this Feature cannot depend on the interpreter it is locating.
NODE=/usr/local/share/nvm/current/bin/node
if [[ ! -x "$NODE" ]]; then
  echo "jq: $NODE is not executable." >&2
  echo "The pinned jq input cannot be installed." >&2
  echo "Remedy: install the declared Node Feature dependency before jq." >&2
  exit 1
fi
exec "$NODE" dist/install.cjs
