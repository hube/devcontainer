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
IMAGE="dc-codex-metadata-assert:$(date +%s)-$$-$RANDOM"
BUILD_LOG="$(mktemp)"
INSPECT_LOG="$(mktemp)"
METADATA="$(mktemp)"
trap 'docker image rm --force "$IMAGE" >/dev/null 2>&1 || true; rm -f "$BUILD_LOG" "$INSPECT_LOG" "$METADATA"' EXIT

fail() {
  local problem=$1 consequence=$2 remedy=$3 tool=$4 output=$5
  printf 'Problem: %s\nConsequence: %s\nRemedy: %s\n%s said: %s\n' \
    "$problem" "$consequence" "$remedy" "$tool" "${output:-<no output>}" >&2
  exit 1
}

if ! npx -y @devcontainers/cli@latest build \
  --workspace-folder "$REPO_ROOT" --image-name "$IMAGE" >"$BUILD_LOG" 2>&1; then
  fail "The Dev Container image build failed." \
    "The Codex feature metadata cannot be verified in a built image." \
    "Fix the Dev Container build error shown below, then rerun this test." \
    "npx devcontainer build" "$(cat "$BUILD_LOG")"
fi

if ! docker inspect "$IMAGE" --format '{{ index .Config.Labels "devcontainer.metadata" }}' \
  >"$METADATA" 2>"$INSPECT_LOG"; then
  fail "Docker could not inspect the built image's devcontainer.metadata label." \
    "The Codex feature's securityOpt and postCreateCommand cannot be verified." \
    "Fix the Docker inspect error shown below, then rerun this test." \
    "docker inspect" "$(cat "$INSPECT_LOG")"
fi

python3 -c '
import json, sys

def fail(problem, consequence, remedy, tool, output):
    print(f"Problem: {problem}", file=sys.stderr)
    print(f"Consequence: {consequence}", file=sys.stderr)
    print(f"Remedy: {remedy}", file=sys.stderr)
    print("{} said: {}".format(tool, output or "<no output>"), file=sys.stderr)
    raise SystemExit(1)

def check(cond, problem, consequence, remedy, output):
    if not cond:
        fail(problem, consequence, remedy, "metadata validation", output)

try:
    meta = json.load(sys.stdin)
except json.JSONDecodeError as exc:
    fail("The built image has a devcontainer.metadata label that is not valid JSON.",
         "The Codex feature metadata cannot be checked for the required security configuration.",
         "Rebuild the image with valid feature metadata, then rerun this test.",
         "python json parser", f"{type(exc).__name__}: {exc}")

check(isinstance(meta, list),
      "The devcontainer.metadata label is not a JSON array.",
      "The Codex feature metadata entry cannot be located reliably.",
      "Rebuild the image so devcontainer.metadata contains the feature metadata array.",
      f"expected a list, got {type(meta).__name__}: {meta!r}")
entries = [e for e in meta if isinstance(e, dict) and e.get("id") == "./local-features/codex"]
check(len(entries) == 1,
      "The built image does not contain exactly one Codex feature metadata entry.",
      "The Codex feature security configuration cannot be selected unambiguously.",
      "Ensure the Codex feature is declared exactly once, rebuild the image, and rerun this test.",
      f"expected exactly one codex metadata entry, got {len(entries)}")
codex = entries[0]

expected_opt = ("seccomp=${localWorkspaceFolder}"
                "/.devcontainer/local-features/codex/seccomp/userns.json")
opts = codex.get("securityOpt") or []
check(isinstance(opts, list) and expected_opt in opts,
      "The Codex metadata entry has a missing or incorrect securityOpt.",
      "Docker may start the container without the seccomp profile Codex needs to apply edits.",
      f"Set securityOpt to include {expected_opt!r}, rebuild the image, and rerun this test.",
      f"securityOpt missing or wrong: {opts}")

expected_hook = "~/bin/devcontainer-feature/codex/postCreateScript.sh"
actual_hook = codex.get("postCreateCommand")
check(actual_hook == expected_hook,
      "The Codex metadata entry has a missing or incorrect postCreateCommand.",
      "Container creation may skip the user-namespace smoke test and surface failures mid-session.",
      f"Set postCreateCommand to {expected_hook!r}, rebuild the image, and rerun this test.",
      f"bad postCreateCommand: {actual_hook}")

print("codex securityOpt and postCreateCommand verified")
' <"$METADATA"
