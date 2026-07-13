#!/usr/bin/env bash
# Verifies the seccomp profile this feature ships actually took effect.
set -uo pipefail

PROFILE=".devcontainer/local-features/codex/seccomp/userns.json"
failed=0

diagnose() {
  local problem="$1" remedy="$2" tool="$3" output="$4"
  {
    echo "codex: $problem"
    echo "codex: Codex's patch helper cannot apply edits, so Codex cannot write files in this container."
    echo "codex: $remedy"
    echo "codex: $tool said: ${output:-no output}"
  } >&2
  failed=1
}

if ! bwrap_path="$(command -v bwrap 2>&1)"; then
  diagnose "Bubblewrap is not installed." \
    "Install the bubblewrap package by rebuilding the container with the Codex feature." \
    "command -v bwrap" "$bwrap_path"
elif ! output="$(bwrap --unshare-all --dev-bind / / true 2>&1)"; then
  diagnose "Bubblewrap cannot start a sandbox." \
    "Check that the Codex feature's securityOpt resolves to $PROFILE on the host, then rebuild the container." \
    bwrap "$output"

  if ! output="$(unshare --user --map-root-user true 2>&1)"; then
    diagnose "creating an unprivileged user namespace is also blocked." \
      "Check that the Codex feature's securityOpt resolves to $PROFILE on the host, then rebuild the container." \
      unshare "$output"
  fi
fi

exit "$failed"
