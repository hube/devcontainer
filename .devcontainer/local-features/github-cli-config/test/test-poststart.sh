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
  export GH_ERROR=""
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
if [[ -n "${GH_ERROR:-}" ]]; then
  printf '%s\n' "$GH_ERROR" >&2
fi
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
[[ "$out" == *"GitHub CLI bootstrap token is unavailable: GH_TOKEN and GITHUB_TOKEN are unset or empty."* ]] && pass "empty tokens: states problem" || fail "empty tokens: states problem" "$out"
[[ "$out" == *"Stored GitHub CLI authentication was not updated."* ]] && pass "empty tokens: states consequence" || fail "empty tokens: states consequence" "$out"
[[ "$out" == *"Set GH_TOKEN or GITHUB_TOKEN on the host, then restart the container."* ]] && pass "empty tokens: states remedy" || fail "empty tokens: states remedy" "$out"
teardown_world

# Unset tokens leave existing credentials alone by never invoking gh.
setup_world
unset GH_TOKEN GITHUB_TOKEN
run_hook
[[ $rc -eq 0 ]] && pass "unset tokens: exits 0" || fail "unset tokens: exits 0" "got $rc"
[[ ! -e "$GH_LOG" ]] && pass "unset tokens: does not invoke gh" || fail "unset tokens: does not invoke gh" "$out"
[[ "$out" == *"GitHub CLI bootstrap token is unavailable: GH_TOKEN and GITHUB_TOKEN are unset or empty."* ]] && pass "unset tokens: states problem" || fail "unset tokens: states problem" "$out"
[[ "$out" == *"Stored GitHub CLI authentication was not updated."* ]] && pass "unset tokens: states consequence" || fail "unset tokens: states consequence" "$out"
[[ "$out" == *"Set GH_TOKEN or GITHUB_TOKEN on the host, then restart the container."* ]] && pass "unset tokens: states remedy" || fail "unset tokens: states remedy" "$out"
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
[[ "$out" == *"github-cli-config: GitHub CLI is unavailable: env:"* ]] && pass "missing gh: wraps diagnostic" || fail "missing gh: wraps diagnostic" "$out"
[[ "$out" == *"No such file or directory"* ]] && pass "missing gh: includes diagnostic detail" || fail "missing gh: includes diagnostic detail" "$out"
[[ "$out" == *"Stored GitHub CLI authentication was not updated."* ]] && pass "missing gh: states consequence" || fail "missing gh: states consequence" "$out"
[[ "$out" == *"Ensure the github-cli feature is installed, then rebuild the container."* ]] && pass "missing gh: states remedy" || fail "missing gh: states remedy" "$out"
teardown_world

# gh login failures must not prevent container startup.
setup_world
export GH_TOKEN="failing-token"
unset GITHUB_TOKEN
export GH_EXIT_CODE=23
export GH_ERROR="gh said: token rejected"
run_hook
[[ $rc -eq 0 ]] && pass "failure: exits 0" || fail "failure: exits 0" "got $rc"
[[ -e "$GH_LOG" ]] && pass "failure: invokes gh" || fail "failure: invokes gh" "$out"
[[ "$out" == *"github-cli-config: GitHub CLI authentication failed: gh said: token rejected."* ]] && pass "failure: wraps diagnostic" || fail "failure: wraps diagnostic" "$out"
[[ "$out" == *"Stored GitHub CLI authentication was not updated."* ]] && pass "failure: states consequence" || fail "failure: states consequence" "$out"
[[ "$out" == *"Verify the token is valid and includes repo, read:org, and gist; then restart the container."* ]] && pass "failure: states remedy" || fail "failure: states remedy" "$out"
teardown_world

printf '\n%d passed, %d failed\n' "$passed" "$failed"
[[ $failed -eq 0 ]]
