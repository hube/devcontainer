#!/usr/bin/env bash
# Tests the GitHub CLI auth bootstrap without using a real token or gh binary.
set -uo pipefail

HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/devcontainer-feature/github-cli-config/postStartScript.sh"
passed=0
failed=0

pass() { printf 'ok   %s\n' "$1"; passed=$((passed + 1)); }
fail() { printf 'FAIL %s\n     %s\n' "$1" "$2"; failed=$((failed + 1)); }

setup_world() {
  WORLD="$(mktemp -d)"
  export HOME="$WORLD/home"
  mkdir -p "$HOME" "$WORLD/stub"
  export GH_LOG="$WORLD/gh.log"
  export GH_EXIT_CODE=0
  export PATH="$WORLD/stub:$PATH"

  cat > "$WORLD/stub/gh" <<'GH'
#!/usr/bin/env bash
{
  printf 'args:'
  printf ' <%s>' "$@"
  printf '\nstdin:'
  IFS= read -r token || true
  printf ' <%s>\n' "$token"
  printf 'GH_TOKEN=%s\n' "${GH_TOKEN-unset}"
  printf 'GITHUB_TOKEN=%s\n' "${GITHUB_TOKEN-unset}"
} > "$GH_LOG"
exit "${GH_EXIT_CODE:-0}"
GH
  chmod +x "$WORLD/stub/gh"
}

teardown_world() { rm -rf "$WORLD"; }

run_hook() {
  out="$("$HOOK" 2>&1)"
  rc=$?
}

# Empty tokens leave existing credentials alone by never invoking gh.
setup_world
export GH_TOKEN=""
export GITHUB_TOKEN=""
run_hook
[[ $rc -eq 0 ]] && pass "empty tokens: exits 0" || fail "empty tokens: exits 0" "got $rc"
[[ ! -e "$GH_LOG" ]] && pass "empty tokens: does not invoke gh" || fail "empty tokens: does not invoke gh" "$out"
[[ "$out" == *"no GitHub CLI auth changes"* ]] && pass "empty tokens: warns" || fail "empty tokens: warns" "$out"
teardown_world

# Unset tokens leave existing credentials alone by never invoking gh.
setup_world
unset GH_TOKEN GITHUB_TOKEN
run_hook
[[ $rc -eq 0 ]] && pass "unset tokens: exits 0" || fail "unset tokens: exits 0" "got $rc"
[[ ! -e "$GH_LOG" ]] && pass "unset tokens: does not invoke gh" || fail "unset tokens: does not invoke gh" "$out"
[[ "$out" == *"no GitHub CLI auth changes"* ]] && pass "unset tokens: warns" || fail "unset tokens: warns" "$out"
teardown_world

# GITHUB_TOKEN is used when GH_TOKEN is empty.
setup_world
export GH_TOKEN=""
export GITHUB_TOKEN="fallback-token"
run_hook
[[ $rc -eq 0 ]] && pass "fallback: exits 0" || fail "fallback: exits 0" "got $rc"
[[ "$(<"$GH_LOG")" == *"stdin: <fallback-token>"* ]] && pass "fallback: sends GITHUB_TOKEN on stdin" || fail "fallback: sends GITHUB_TOKEN on stdin" "$(<"$GH_LOG")"
teardown_world

# GH_TOKEN takes precedence and the child gh process receives no token variables.
setup_world
export GH_TOKEN="preferred-token"
export GITHUB_TOKEN="fallback-token"
run_hook
log="$(<"$GH_LOG")"
[[ $rc -eq 0 ]] && pass "precedence: exits 0" || fail "precedence: exits 0" "got $rc"
[[ "$log" == *"stdin: <preferred-token>"* ]] && pass "precedence: sends GH_TOKEN on stdin" || fail "precedence: sends GH_TOKEN on stdin" "$log"
[[ "$log" == *"GH_TOKEN=unset"* && "$log" == *"GITHUB_TOKEN=unset"* ]] && pass "environment: clears token variables for gh" || fail "environment: clears token variables for gh" "$log"
[[ "$log" == *"args: <auth> <login> <--hostname> <github.com> <--with-token> <--insecure-storage>"* ]] && pass "arguments: uses expected gh auth login flags" || fail "arguments: uses expected gh auth login flags" "$log"
args_line="$(sed -n '1p' "$GH_LOG")"
[[ "$args_line" != *"preferred-token"* ]] && pass "arguments: token is stdin-only" || fail "arguments: token is stdin-only" "$log"
teardown_world

# A missing gh binary must not prevent container startup.
setup_world
export GH_TOKEN="orphan-token"
unset GITHUB_TOKEN
mkdir -p "$WORLD/bin"
ln -s "$(command -v bash)" "$WORLD/bin/bash"
ln -s "$(command -v env)" "$WORLD/bin/env"
out="$(PATH="$WORLD/bin" "$HOOK" 2>&1)"
rc=$?
[[ $rc -eq 0 ]] && pass "missing gh: exits 0" || fail "missing gh: exits 0" "got $rc"
[[ ! -e "$GH_LOG" ]] && pass "missing gh: never reaches a gh binary" || fail "missing gh: never reaches a gh binary" "$out"
[[ "$out" == *"failed"* ]] && pass "missing gh: warns" || fail "missing gh: warns" "$out"
teardown_world

# gh login failures must not prevent container startup.
setup_world
export GH_TOKEN="failing-token"
unset GITHUB_TOKEN
export GH_EXIT_CODE=23
run_hook
[[ $rc -eq 0 ]] && pass "failure: exits 0" || fail "failure: exits 0" "got $rc"
[[ -e "$GH_LOG" ]] && pass "failure: invokes gh" || fail "failure: invokes gh" "$out"
[[ "$out" == *"failed"* ]] && pass "failure: warns" || fail "failure: warns" "$out"
teardown_world

printf '\n%d passed, %d failed\n' "$passed" "$failed"
[[ $failed -eq 0 ]]
