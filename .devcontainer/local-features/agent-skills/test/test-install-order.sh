#!/usr/bin/env bash
# Asserts that dependsOn puts ssh and workspaces-permissions ahead of
# agent-skills, so their postStart hooks run first. A mistyped installsAfter id
# is silently ignored by the CLI, so this must be asserted, never assumed.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
IMAGE="dc-order-assert:latest"

npx -y @devcontainers/cli@latest build \
  --workspace-folder "$REPO_ROOT" --image-name "$IMAGE" >/dev/null 2>&1

docker inspect "$IMAGE" --format '{{ index .Config.Labels "devcontainer.metadata" }}' \
  | python3 -c '
import json, sys
meta = json.load(sys.stdin)
ids = [e["id"] for e in meta if e.get("id")]
for dep in ("./local-features/ssh", "./local-features/workspaces-permissions"):
    assert dep in ids, f"{dep} missing from metadata: {ids}"
    assert ids.index(dep) < ids.index("./local-features/agent-skills"), \
        f"{dep} must install before ./local-features/agent-skills, got {ids}"
hook = next(e for e in meta if e.get("id") == "./local-features/agent-skills")
expected = "~/bin/devcontainer-feature/agent-skills/postStartScript.sh"
actual = hook.get("postStartCommand")
assert actual == expected, f"bad hook: {actual}"
print("install order and postStartCommand verified")
'
