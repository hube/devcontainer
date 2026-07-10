#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${_CONTAINER_USER:-}" ]] || ! id "${_CONTAINER_USER}" >/dev/null 2>&1; then
  echo "github-cli-config: container user '${_CONTAINER_USER:-}' does not exist" >&2
  exit 1
fi

user_home="/home/${_CONTAINER_USER}"

rsync -rp \
  --chown="${_CONTAINER_USER}:${_CONTAINER_USER}" \
  --chmod=D755,F755 \
  bin "${user_home}"
