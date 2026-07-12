#!/usr/bin/env bash
# Tests postCreateScript.sh's success and failure paths without rebuilding the
# container. The failure path is forced by stubbing `unshare` and `bwrap` on
# PATH, so the test does not depend on the host's namespace policy.
set -uo pipefail

HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/devcontainer-feature/codex/postCreateScript.sh"
passed=0
failed=0

pass() { printf 'ok   %s\n' "$1"; passed=$((passed + 1)); }
fail() { printf 'FAIL %s\n     %s\n' "$1" "$2"; failed=$((failed + 1)); }

[[ -x "$HOOK" ]] && pass "hook: is executable" || fail "hook: is executable" "$HOOK"

run_hook() {
  local dir; dir="$(mktemp -d)"
  printf '#!/usr/bin/env bash\n[[ %s -eq 0 ]] || echo "%s" >&2\nexit %s\n' "$1" "$3" "$1" > "$dir/unshare"
  printf '#!/usr/bin/env bash\n[[ %s -eq 0 ]] || echo "%s" >&2\nexit %s\n' "$2" "$3" "$2" > "$dir/bwrap"
  chmod +x "$dir/unshare" "$dir/bwrap"
  OUT="$(PATH="$dir:$PATH" "$HOOK" 2>&1)"; RC=$?
  rm -rf "$dir"
}

run_hook 0 0 ""
[[ $RC -eq 0 ]] && pass "success: exits 0 when namespaces work" \
  || fail "success: exits 0 when namespaces work" "rc=$RC out=$OUT"

run_hook 1 0 "unshare: Operation not permitted"
[[ $RC -ne 0 ]] && pass "userns blocked: fails the container create" \
  || fail "userns blocked: fails the container create" "exited 0"
[[ "$OUT" == *"user namespace"* ]] && pass "userns blocked: names the problem" \
  || fail "userns blocked: names the problem" "$OUT"
[[ "$OUT" == *"cannot apply edits"* ]] && pass "userns blocked: names the consequence" \
  || fail "userns blocked: names the consequence" "$OUT"

[[ "$OUT" == *"seccomp/userns.json"* && "$OUT" == *"rebuild"* ]] \
  && pass "userns blocked: names the remedy" \
  || fail "userns blocked: names the remedy" "$OUT"
[[ "$OUT" == *"unshare said: unshare: Operation not permitted"* ]] \
  && pass "userns blocked: relays the underlying error" \
  || fail "userns blocked: relays the underlying error" "$OUT"

missing_dir="$(mktemp -d)"
ln -s "$(command -v bash)" "$missing_dir/bash"
ln -s "/usr/bin/true" "$missing_dir/unshare"
OUT="$(PATH="$missing_dir" "$HOOK" 2>&1)"; RC=$?
rm -rf "$missing_dir"
[[ $RC -ne 0 ]] && pass "bwrap missing: fails the container create" || fail "bwrap missing: fails the container create" "exited 0"
[[ "$OUT" == *"Bubblewrap is not installed"* ]] && pass "bwrap missing: names the problem" || fail "bwrap missing: names the problem" "$OUT"
[[ "$OUT" == *"cannot apply edits"* ]] && pass "bwrap missing: names the consequence" || fail "bwrap missing: names the consequence" "$OUT"
[[ "$OUT" == *"bubblewrap package"* && "$OUT" == *"rebuild"* ]] && pass "bwrap missing: names the package remedy" || fail "bwrap missing: names the package remedy" "$OUT"
[[ "$OUT" == *"command -v bwrap said: no output"* ]] && pass "bwrap missing: frames the underlying lookup output" || fail "bwrap missing: frames the underlying lookup output" "$OUT"

run_hook 0 1 "bwrap: No permissions to create a new namespace"
[[ $RC -ne 0 ]] && pass "bwrap blocked: fails the container create" \
  || fail "bwrap blocked: fails the container create" "exited 0"
[[ "$OUT" == *"Bubblewrap"* ]] && pass "bwrap blocked: distinct message from the userns case" \
  || fail "bwrap blocked: distinct message from the userns case" "$OUT"
[[ "$OUT" == *"bwrap said: bwrap: No permissions"* ]] \
  && pass "bwrap blocked: relays the underlying error" \
  || fail "bwrap blocked: relays the underlying error" "$OUT"

run_hook 1 1 "namespace probe failed"
[[ $RC -ne 0 ]] && pass "combined blocked: fails the container create" \
  || fail "combined blocked: fails the container create" "exited 0"
[[ "$OUT" == *"unshare said: namespace probe failed"* ]] \
  && pass "combined blocked: reports the unshare failure" \
  || fail "combined blocked: reports the unshare failure" "$OUT"
[[ "$OUT" == *"bwrap said: namespace probe failed"* ]] \
  && pass "combined blocked: reports the bwrap failure" \
  || fail "combined blocked: reports the bwrap failure" "$OUT"

missing_dir="$(mktemp -d)"
ln -s "$(command -v bash)" "$missing_dir/bash"
printf '#!/usr/bin/env bash\necho "unshare combined failure" >&2\nexit 1\n' > "$missing_dir/unshare"
chmod +x "$missing_dir/unshare"
OUT="$(PATH="$missing_dir" "$HOOK" 2>&1)"; RC=$?
rm -rf "$missing_dir"
[[ $RC -ne 0 ]] && pass "combined missing: fails the container create" \
  || fail "combined missing: fails the container create" "exited 0"
[[ "$OUT" == *"unshare said: unshare combined failure"* ]] \
  && pass "combined missing: reports the unshare failure" \
  || fail "combined missing: reports the unshare failure" "$OUT"
[[ "$OUT" == *"command -v bwrap said: no output"* ]] \
  && pass "combined missing: reports the missing bwrap failure" \
  || fail "combined missing: reports the missing bwrap failure" "$OUT"
INSTALL="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/install.sh"

installs_bubblewrap() {
  grep -Eq '^[[:space:]]*apt-get[[:space:]]+install([[:space:]]+[^[:space:]]+)*[[:space:]]+bubblewrap([[:space:]]|$)' "$1"
}

installs_bubblewrap "$INSTALL" \
  && pass "install: installs bubblewrap explicitly" \
  || fail "install: installs bubblewrap explicitly" "the hook's bwrap would depend on another feature's package list"

mutated_install="$(mktemp)"
sed '/^[[:space:]]*apt-get[[:space:]]\+install.*[[:space:]]bubblewrap[[:space:]]*$/d' "$INSTALL" > "$mutated_install"
if installs_bubblewrap "$mutated_install"; then
  fail "install assertion: rejects a copy without the install command" \
    "comments or output text satisfied the explicit dependency assertion"
else
  pass "install assertion: rejects a copy without the install command"
fi
rm -f "$mutated_install"
printf '\n%d passed, %d failed\n' "$passed" "$failed"
[[ $failed -eq 0 ]]
