#!/usr/bin/env bash
# Asserts that dependsOn puts ssh and workspaces-permissions ahead of
# agent-skills, so their postStart hooks run first. A mistyped installsAfter id
# is silently ignored by the CLI, so this must be asserted, never assumed.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
IMAGE="dc-order-assert:latest"
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
check("./local-features/agent-skills" in ids,
      f"./local-features/agent-skills missing from metadata: {ids}")
for dep in ("./local-features/ssh", "./local-features/workspaces-permissions"):
    check(dep in ids, f"{dep} missing from metadata: {ids}")
    check(ids.index(dep) < ids.index("./local-features/agent-skills"),
          f"{dep} must install before ./local-features/agent-skills, got {ids}")
hooks = [e for e in meta if e.get("id") == "./local-features/agent-skills"]
check(len(hooks) == 1, f"expected exactly one agent-skills metadata entry, got {len(hooks)}")
hook = hooks[0]
expected = "~/bin/devcontainer-feature/agent-skills/postStartScript.sh"
actual = hook.get("postStartCommand")
check(actual == expected, f"bad hook: {actual}")
print("install order and postStartCommand verified")
'
