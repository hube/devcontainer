#!/usr/bin/env bash
# Verifies the seccomp profile this feature ships actually took effect.
set -uo pipefail

PROFILE=".devcontainer/local-features/codex/seccomp/userns.json"

die() {
  local problem="$1" tool="$2" output="$3"
  {
    echo "codex: $problem"
    echo "codex: Codex's patch helper cannot apply edits, so Codex cannot write files in this container."
    echo "codex: Check that the Codex feature's securityOpt resolves to $PROFILE on the host, then rebuild the container."
    echo "codex: $tool said: ${output:-no output}"
  } >&2
  exit 1
}

if ! output="$(unshare --user --map-root-user true 2>&1)"; then
  die "creating an unprivileged user namespace is blocked." unshare "$output"
fi

if ! output="$(bwrap --unshare-all --dev-bind / / true 2>&1)"; then
  die "Bubblewrap cannot start a sandbox even though user namespaces work." bwrap "$output"
fi

exit 0
