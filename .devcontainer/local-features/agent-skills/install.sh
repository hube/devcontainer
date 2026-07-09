#!/usr/bin/env bash
# Feature options reach install.sh and nothing else, so persist them for the
# postStart hook to source.
set -euo pipefail

errors=()

[[ -n "${REPO:-}" ]] || errors+=("option 'repo' must not be empty")

if [[ -z "${CLONEDIR:-}" ]]; then
  errors+=("option 'cloneDir' must not be empty")
elif [[ "${CLONEDIR}" != /* ]]; then
  errors+=("option 'cloneDir' must be an absolute path, got '${CLONEDIR}'")
fi

if [[ -z "${_CONTAINER_USER:-}" ]] || ! id "${_CONTAINER_USER}" >/dev/null 2>&1; then
  errors+=("container user '${_CONTAINER_USER:-}' does not exist")
fi

if (( ${#errors[@]} > 0 )); then
  printf 'agent-skills: %s\n' "${errors[@]}" >&2
  exit 1
fi

echo ">Installing agent-skills bootstrap"

user_home="/home/${_CONTAINER_USER}"

rsync -rp \
    --chown="${_CONTAINER_USER}:${_CONTAINER_USER}" \
    --chmod=D755,F755 \
    bin "${user_home}"

env_dir="${user_home}/.config/devcontainer-feature"
install -d -o "${_CONTAINER_USER}" -g "${_CONTAINER_USER}" -m 0755 "${env_dir}"

env_file="${env_dir}/agent-skills.env"
{
  printf 'AGENT_SKILLS_REPO=%q\n' "${REPO}"
  printf 'AGENT_SKILLS_CLONE_DIR=%q\n' "${CLONEDIR}"
} > "${env_file}"
chown "${_CONTAINER_USER}:${_CONTAINER_USER}" "${env_file}"
chmod 0644 "${env_file}"

echo ">Done installing agent-skills bootstrap"
