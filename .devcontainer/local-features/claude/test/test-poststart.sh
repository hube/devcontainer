#!/usr/bin/env bash
# Tests the shared-instructions mount warning. The hook must never fail
# container start, and must distinguish "absent" from "present but not a
# directory" — the two need different remedies.
set -uo pipefail

HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/devcontainer-feature/claude/postStartScript.sh"
passed=0
failed=0

pass() { printf 'ok   %s\n' "$1"; passed=$((passed + 1)); }
fail() { printf 'FAIL %s\n     %s\n' "$1" "$2"; failed=$((failed + 1)); }

setup_world() {
  WORLD="$(mktemp -d)"
  export HOME="$WORLD/home"
  mkdir -p "$HOME"
}

teardown_world() { rm -rf "$WORLD"; }

run_hook() {
  out="$("$HOOK" 2>&1)"
  rc=$?
}

# A present directory is the healthy case: exit 0, say nothing.
setup_world
mkdir -p "$HOME/.agents/instructions"
run_hook
[[ $rc -eq 0 ]] && pass "mounted: exits 0" || fail "mounted: exits 0" "got $rc"
[[ -z "$out" ]] && pass "mounted: stays silent" || fail "mounted: stays silent" "$out"
teardown_world

# An absent directory warns without blocking container start.
setup_world
run_hook
[[ $rc -eq 0 ]] && pass "absent: exits 0" || fail "absent: exits 0" "got $rc"
[[ "$out" == *"claude: $HOME/.agents/instructions is absent, so the shared agent instructions are not mounted."* ]] && pass "absent: states problem" || fail "absent: states problem" "$out"
[[ "$out" == *"Claude Code cannot resolve the ~/.agents/instructions pointer in CLAUDE.md, so the rigor-levels reference and the reviewer dispatch blocks are unavailable."* ]] && pass "absent: states consequence" || fail "absent: states consequence" "$out"
[[ "$out" == *"Add the consumer mount documented in hube/devcontainer's .devcontainer/local-features/claude/NOTES.md to devcontainer.json, ensure ~/.claude/instructions exists on the host, then restart the container."* ]] && pass "absent: states remedy" || fail "absent: states remedy" "$out"
teardown_world

# A non-directory at the target needs a different remedy than an absent one.
setup_world
mkdir -p "$HOME/.agents"
: > "$HOME/.agents/instructions"
run_hook
[[ $rc -eq 0 ]] && pass "not a directory: exits 0" || fail "not a directory: exits 0" "got $rc"
[[ "$out" == *"claude: $HOME/.agents/instructions exists but is not a directory, so the shared agent instructions cannot be read."* ]] && pass "not a directory: states problem" || fail "not a directory: states problem" "$out"
[[ "$out" == *"Remove it, declare the consumer mount documented in hube/devcontainer's .devcontainer/local-features/claude/NOTES.md, then restart the container. If ~/.claude/instructions on the host is itself a file rather than a directory, replace it with a directory on the host, because declaring the mount cannot fix a file at the mount's source."* ]] && pass "not a directory: states remedy" || fail "not a directory: states remedy" "$out"
[[ "$out" != *"is absent"* ]] && pass "not a directory: does not report absence" || fail "not a directory: does not report absence" "$out"
teardown_world

# The manifest must actually run the hook, or none of the above ever executes.
manifest_command="$(python3 -c "
import json, re, sys
raw = open('$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/devcontainer-feature.json').read()
print(json.loads(re.sub(r'(?m)^\s*//.*$', '', raw)).get('postStartCommand', ''))
")"
[[ "$manifest_command" == "~/bin/devcontainer-feature/claude/postStartScript.sh" ]] && pass "manifest: declares postStartCommand" || fail "manifest: declares postStartCommand" "got '$manifest_command'"

# install.sh must copy bin/ executable, or the declared hook is never installed.
install_sh="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/install.sh"
grep -q 'F755' "$install_sh" && grep -q '"bin/\."' "$install_sh" && pass "install: copies bin executable" || fail "install: copies bin executable" "install.sh does not rsync bin/. with F755"

printf '\n%d passed, %d failed\n' "$passed" "$failed"
[[ $failed -eq 0 ]]
