#!/usr/bin/env bash
# Verifies the configuration this repo owns: that its own consumer
# devcontainer.json declares the shared-instructions mount with the source,
# target, and read-only flag the Features' target path depends on. Docker's
# enforcement of a correctly declared read-only bind is assumed, not retested.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
CONSUMER="$ROOT/.devcontainer/devcontainer.json"

python3 - "$CONSUMER" <<'PY'
import json, re, sys
from pathlib import Path

raw = Path(sys.argv[1]).read_text(encoding="utf-8")
config = json.loads(re.sub(r"(?m)^\s*//.*$", "", raw))

EXPECTED_SOURCE = "${localEnv:HOME}/.claude/instructions"
EXPECTED_TARGET = "/home/${localEnv:USERNAME:devcontainer}/.agents/instructions"

failures = []
mounts = config.get("mounts", [])
matching = [m for m in mounts if isinstance(m, dict) and m.get("target") == EXPECTED_TARGET]

if not matching:
    failures.append(
        f"consumer devcontainer.json declares no mount targeting {EXPECTED_TARGET}"
    )
elif len(matching) > 1:
    failures.append(
        f"consumer devcontainer.json declares {len(matching)} mounts targeting "
        f"{EXPECTED_TARGET}; the mount is declared once for the whole container"
    )
else:
    mount = matching[0]
    if mount.get("source") != EXPECTED_SOURCE:
        failures.append(
            f"instructions mount source is {mount.get('source')!r}, expected {EXPECTED_SOURCE!r}"
        )
    if "readonly" not in str(mount.get("type", "")):
        failures.append(
            f"instructions mount type is {mount.get('type')!r}, which is not read-only"
        )

if failures:
    print("FAIL")
    for failure in failures:
        print(f"  {failure}")
    raise SystemExit(1)

print("ok   consumer devcontainer.json declares the read-only instructions mount")
PY
