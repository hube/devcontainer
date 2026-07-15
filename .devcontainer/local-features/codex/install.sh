#!/usr/bin/env bash
set -euo pipefail

# Install OpenAI Codex CLI. Installation script originally copied from
# https://developers.openai.com/codex/cli

if [[ -z "${_CONTAINER_USER:-}" ]]
then
  printf '%s\n' \
    "Codex container user validation failed. Codex cannot install its configuration or CLI. Set _CONTAINER_USER to an existing account and rebuild the container. validation said: _CONTAINER_USER is unset or empty" >&2
  exit 1
fi

container_user_id="$(id -u "${_CONTAINER_USER}" 2>&1)" || {
  status=$?
  printf '%s\n' \
    "Codex container user validation failed for '${_CONTAINER_USER}'. Codex cannot install its configuration or CLI. Set _CONTAINER_USER to an existing account and rebuild the container. id said: ${container_user_id:-id exited with status $status without diagnostic output}" >&2
  exit "$status"
}

if [[ "$container_user_id" -eq 0 ]]
then
  printf '%s\n' \
    "Codex container user validation failed for '${_CONTAINER_USER}'. Codex cannot safely install Bubblewrap or the CLI as the intended user. Set _CONTAINER_USER to an existing non-root account and rebuild the container. id said: '${_CONTAINER_USER}' resolved to UID $container_user_id" >&2
  exit 1
fi

if [[ $EUID -ne $container_user_id ]]
then
  apt_output="$(apt-get update 2>&1 && DEBIAN_FRONTEND=noninteractive \
    apt-get install -y bubblewrap 2>&1)" || {
    status=$?
    printf '%s\n' \
      "Codex system Bubblewrap installation failed. Codex cannot create its Linux sandbox. Verify apt sources and rebuild the container. apt said: ${apt_output:-apt exited with status $status without diagnostic output}" >&2
    exit "$status"
  }
  configure_output="$({
    chown root:root /usr/bin/bwrap && chmod 4755 /usr/bin/bwrap
  } 2>&1)" || {
    status=$?
    printf '%s\n' \
      "Codex system Bubblewrap configuration failed. Codex cannot safely create its Linux sandbox. Ensure the container build runs the Feature installer as root, then rebuild. chown/chmod said: ${configure_output:-configuration exited with status $status without diagnostic output}" >&2
    exit "$status"
  }
  bwrap_metadata="$(stat -c '%U:%G %a' /usr/bin/bwrap 2>&1)" || {
    status=$?
    printf '%s\n' \
      "Codex system Bubblewrap verification failed. Codex cannot create its Linux sandbox. Rebuild the container after confirming the bubblewrap package installs /usr/bin/bwrap. stat said: ${bwrap_metadata:-stat exited with status $status without diagnostic output}" >&2
    exit "$status"
  }
  if [[ "$bwrap_metadata" != "root:root 4755" ]]; then
    printf '%s\n' \
      "Codex system Bubblewrap has invalid ownership or mode: $bwrap_metadata. Codex cannot safely create its Linux sandbox. Ensure /usr/bin/bwrap is root:root with mode 4755, then rebuild the container. stat said: $bwrap_metadata" >&2
    exit 1
  fi

  echo ">Copying config to the remote user's home directory"

  # Copy files over while setting ownership and permissions
  copy_output="$(rsync -rp \
      --chown=${_CONTAINER_USER}:${_CONTAINER_USER} \
      --chmod=D755,F644 \
      home/. /home/${_CONTAINER_USER} 2>&1)" || {
    status=$?
    printf '%s\n' \
      "Codex configuration copy failed. Codex cannot install its configuration for the container user. Verify the Feature files and target home permissions, then rebuild. rsync said: ${copy_output:-rsync exited with status $status without diagnostic output}" >&2
    exit "$status"
  }

  installer_path="$(realpath "$0" 2>&1)" || {
    status=$?
    printf '%s\n' \
      "Codex user re-execution preparation failed. Codex cannot install its CLI as the container user. Verify the Feature installer path and rebuild. realpath said: ${installer_path:-realpath exited with status $status without diagnostic output}" >&2
    exit "$status"
  }
  user_install_output="$(sudo -iu "${_CONTAINER_USER}" "$installer_path" 2>&1)" || {
    status=$?
    printf '%s\n' \
      "Codex user re-execution failed. Codex cannot install its CLI as the container user. Verify sudo can start the configured container user, then rebuild. sudo said: ${user_install_output:-sudo exited with status $status without diagnostic output}" >&2
    exit "$status"
  }
  if [[ -n "$user_install_output" ]]; then
    printf '%s\n' "$user_install_output"
  fi
  exit 0
fi

echo ">Switched to the container user"

echo ">Installing Codex CLI"

codex_install_output="$({
  curl -fsSL https://chatgpt.com/codex/install.sh | CODEX_NON_INTERACTIVE=1 sh
} 2>&1)" || {
  status=$?
  printf '%s\n' \
    "Codex CLI installation failed. Codex is unavailable in the container. Verify network access to chatgpt.com and rebuild. installer said: ${codex_install_output:-installer exited with status $status without diagnostic output}" >&2
  exit "$status"
}
if [[ -n "$codex_install_output" ]]; then
  printf '%s\n' "$codex_install_output"
fi

echo ">Done installing Codex CLI"
