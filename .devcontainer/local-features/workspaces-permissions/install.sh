#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${_CONTAINER_USER:-}" ]] || ! id "${_CONTAINER_USER}" >/dev/null 2>&1; then
  echo "Container user '${_CONTAINER_USER:-}' does not exist" >&2
  exit 1
fi

install -d -o "${_CONTAINER_USER}" -g "${_CONTAINER_USER}" -m 0755 /workspaces
