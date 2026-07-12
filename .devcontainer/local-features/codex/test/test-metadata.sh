#!/usr/bin/env bash
# Asserts the Codex feature's securityOpt and postCreateCommand actually reach
# the built image's devcontainer.metadata label. A typo in either is silently
# ignored by the CLI, so this must be asserted, never assumed.
#
# The label stores metadata *unsubstituted*, so the expected securityOpt still
# contains the literal ${localWorkspaceFolder}; the CLI resolves it against the
# host checkout when the container is created.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
IMAGE="dc-codex-metadata-assert:latest"
BUILD_LOG="$(mktemp)"
trap 'rm -f "$BUILD_LOG"' EXIT

if ! npx -y @devcontainers/cli@latest build \
  --workspace-folder "$REPO_ROOT" --image-name "$IMAGE" >"$BUILD_LOG" 2>&1; then
  cat "$BUILD_LOG"
  exit 1
fi

docker inspect "$IMAGE" --format '{{ index .Config.Labels "devcontainer.metadata" }}' \
  | python3 -c '
import json, sys

def check(cond, msg):
    # Bare assert is stripped under PYTHONOPTIMIZE/-O, which would make this
    # script print success unconditionally on a real regression.
    if not cond:
        raise SystemExit(msg)

meta = json.load(sys.stdin)
entries = [e for e in meta if e.get("id") == "./local-features/codex"]
check(len(entries) == 1, f"expected exactly one codex metadata entry, got {len(entries)}")
codex = entries[0]

expected_opt = ("seccomp=${localWorkspaceFolder}"
                "/.devcontainer/local-features/codex/seccomp/userns.json")
opts = codex.get("securityOpt") or []
check(expected_opt in opts, f"securityOpt missing or wrong: {opts}")

expected_hook = "~/bin/devcontainer-feature/codex/postCreateScript.sh"
actual_hook = codex.get("postCreateCommand")
check(actual_hook == expected_hook, f"bad postCreateCommand: {actual_hook}")

print("codex securityOpt and postCreateCommand verified")
'
