#!/usr/bin/env bash
# Asserts that ghcr.io/devcontainers/features/node installs before
# ./local-features/git-commit-attribution (the Feature's own dependsOn — see
# devcontainer-feature.json), and that the metadata carries exactly one
# git-commit-attribution entry with the expected postStartCommand. A mistyped
# dependsOn id is silently ignored by the CLI, so this must be asserted, never
# assumed.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
IMAGE="dc-gca-order-assert:latest"
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
    # script print success unconditionally on a real ordering regression.
    if not cond:
        raise SystemExit(msg)

meta = json.load(sys.stdin)
ids = [e["id"] for e in meta if e.get("id")]
check("./local-features/git-commit-attribution" in ids,
      f"./local-features/git-commit-attribution missing from metadata: {ids}")
check("ghcr.io/devcontainers/features/node:2" in ids,
      f"ghcr.io/devcontainers/features/node:2 missing from metadata: {ids}")
check(ids.index("ghcr.io/devcontainers/features/node:2")
      < ids.index("./local-features/git-commit-attribution"),
      "ghcr.io/devcontainers/features/node:2 must install before "
      f"./local-features/git-commit-attribution, got {ids}")
hooks = [e for e in meta if e.get("id") == "./local-features/git-commit-attribution"]
check(len(hooks) == 1,
      f"expected exactly one git-commit-attribution metadata entry, got {len(hooks)}")
hook = hooks[0]
expected = "~/bin/devcontainer-feature/git-commit-attribution/postStartScript.sh"
actual = hook.get("postStartCommand")
check(actual == expected, f"bad hook: {actual}")
print("install order and postStartCommand verified")
'
