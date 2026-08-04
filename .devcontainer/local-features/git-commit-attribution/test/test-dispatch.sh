#!/usr/bin/env bash
# Tests dispatch.sh: the chaining hook dispatcher installed under every
# githooks(5) name via core.hooksPath. The validator is a stub the tests
# control (exit code + output); the real bundle is exercised in Task 8's
# integration suite. All git activity happens inside a tmp world steered by
# GIT_CONFIG_SYSTEM so this suite never touches the ambient git config.
set -uo pipefail

DISPATCH="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/dispatch.sh"
passed=0
failed=0

pass() { printf 'ok   %s\n' "$1"; passed=$((passed + 1)); }
fail() { printf 'FAIL %s\n     %s\n' "$1" "$2"; failed=$((failed + 1)); }

# Every githooks(5) name install.sh will symlink. Kept local to the test
# rather than sourced from install.sh, which does not exist yet (Task 7).
HOOK_NAMES="applypatch-msg pre-applypatch post-applypatch pre-commit
pre-merge-commit prepare-commit-msg commit-msg post-commit pre-rebase
post-checkout post-merge pre-push pre-receive update proc-receive
post-receive post-update reference-transaction push-to-checkout
pre-auto-gc post-rewrite sendemail-validate fsmonitor-watchman
p4-changelist p4-prepare-changelist p4-post-changelist p4-pre-submit
post-index-change"

# Builds an isolated world: a GATE_DIR hooks farm (dispatch + one symlink per
# githooks(5) name, exactly as install.sh will build it), a stub validate
# under GCA_ROOT whose exit code/output/invocation-log the test controls, a
# fake-but-executable GCA_NODE (dispatch only checks -x on it, never execs
# it), and GIT_CONFIG_SYSTEM pointing scratch git repos at the farm via
# core.hooksPath. Nothing here touches this worktree's own repo or the
# ambient git config.
setup_world() {
  WORLD="$(mktemp -d)"

  GATE_DIR="$WORLD/gate"
  mkdir -p "$GATE_DIR/hooks"
  cp "$DISPATCH" "$GATE_DIR/hooks/dispatch"
  chmod +x "$GATE_DIR/hooks/dispatch"
  for name in $HOOK_NAMES; do
    ln -s dispatch "$GATE_DIR/hooks/$name"
  done

  export GCA_ROOT="$WORLD/gca-root"
  mkdir -p "$GCA_ROOT"
  VALIDATOR_LOG="$WORLD/validator.log"
  VALIDATOR_RC="$WORLD/validator-rc"
  VALIDATOR_OUT="$WORLD/validator-out"
  : > "$VALIDATOR_LOG"
  printf '0\n' > "$VALIDATOR_RC"
  : > "$VALIDATOR_OUT"
  export VALIDATOR_LOG VALIDATOR_RC VALIDATOR_OUT
  cat > "$GCA_ROOT/validate" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >> "$VALIDATOR_LOG"
if [ -s "$VALIDATOR_OUT" ]; then
  cat "$VALIDATOR_OUT" >&2
fi
rc=0
[ -s "$VALIDATOR_RC" ] && rc="$(cat "$VALIDATOR_RC")"
exit "$rc"
STUB
  chmod +x "$GCA_ROOT/validate"

  export GCA_NODE="$WORLD/bin/node"
  mkdir -p "$WORLD/bin"
  printf '#!/bin/sh\nexit 0\n' > "$GCA_NODE"
  chmod +x "$GCA_NODE"

  export GIT_CONFIG_SYSTEM="$WORLD/gitconfig"
  cat > "$GIT_CONFIG_SYSTEM" <<EOF
[core]
	hooksPath = $GATE_DIR/hooks
EOF
  # Isolate from any real global/system config on the host running this suite.
  export GIT_CONFIG_GLOBAL="$WORLD/no-such-global-config"
}

teardown_world() { rm -rf "$WORLD"; }

# $1 = git-common-dir (e.g. "$repo/.git"), $2 = hook name, $3 = script body,
# $4 = "no" to leave the hook non-executable (default executable).
write_hook() {
  dir="$1/hooks"
  mkdir -p "$dir"
  path="$dir/$2"
  printf '#!/bin/sh\n%s\n' "$3" > "$path"
  if [ "${4:-yes}" != "no" ]; then
    chmod +x "$path"
  fi
}

git_c() {
  repo="$1"; shift
  git -C "$repo" -c user.email=t@t -c user.name=t "$@"
}

validator_call_count() {
  [ -s "$VALIDATOR_LOG" ] && wc -l < "$VALIDATOR_LOG" || echo 0
}

# ============================================================ 1: pre-commit chains, non-zero blocks
setup_world
repo="$WORLD/repo1"; git init --quiet -b main "$repo"
write_hook "$repo/.git" pre-commit "touch '$WORLD/precommit-marker'; exit 1"
out="$(git_c "$repo" commit --quiet --allow-empty -m first 2>&1)"; rc=$?
[ -f "$WORLD/precommit-marker" ] && pass "pre-commit: repo hook runs (marker)" || fail "pre-commit: repo hook runs (marker)" "$out"
[ "$rc" -ne 0 ] && pass "pre-commit: non-zero status blocks the commit" || fail "pre-commit: non-zero status blocks the commit" "exit $rc: $out"
git -C "$repo" rev-parse HEAD >/dev/null 2>&1 && fail "pre-commit: no commit created" "HEAD exists" || pass "pre-commit: no commit created"
teardown_world

# ============================================================ 2: commit-msg repo hook runs after validator PASS; non-zero blocks
setup_world
repo="$WORLD/repo2"; git init --quiet -b main "$repo"
write_hook "$repo/.git" commit-msg "touch '$WORLD/commitmsg-marker'; exit 1"
out="$(git_c "$repo" commit --quiet --allow-empty -m first 2>&1)"; rc=$?
[ "$(validator_call_count)" = "1" ] && pass "commit-msg chain: validator ran once (PASS)" || fail "commit-msg chain: validator ran once (PASS)" "log: $(cat "$VALIDATOR_LOG")"
[ -f "$WORLD/commitmsg-marker" ] && pass "commit-msg chain: repo commit-msg hook runs after PASS" || fail "commit-msg chain: repo commit-msg hook runs after PASS" "$out"
[ "$rc" -ne 0 ] && pass "commit-msg chain: repo hook's non-zero status blocks" || fail "commit-msg chain: repo hook's non-zero status blocks" "exit $rc: $out"
git -C "$repo" rev-parse HEAD >/dev/null 2>&1 && fail "commit-msg chain: no commit created" "HEAD exists" || pass "commit-msg chain: no commit created"
teardown_world

# ============================================================ 3: repo hook present but not executable -> warning, treated as absent
setup_world
repo="$WORLD/repo3"; git init --quiet -b main "$repo"
write_hook "$repo/.git" pre-commit "touch '$WORLD/should-not-run'" no
out="$(git_c "$repo" commit --quiet --allow-empty -m first 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && pass "non-executable hook: commit succeeds" || fail "non-executable hook: commit succeeds" "exit $rc: $out"
[ ! -f "$WORLD/should-not-run" ] && pass "non-executable hook: treated as absent (did not run)" || fail "non-executable hook: treated as absent (did not run)" "marker exists"
[[ "$out" == *"exists but is not executable"* ]] && pass "non-executable hook: warns" || fail "non-executable hook: warns" "$out"
teardown_world

# ============================================================ 4: commit-msg, stub validator exits 1 -> commit not created; stderr reached user
setup_world
repo="$WORLD/repo4"; git init --quiet -b main "$repo"
printf '1\n' > "$VALIDATOR_RC"
printf 'custom validator rejection text\n' > "$VALIDATOR_OUT"
out="$(git_c "$repo" commit --quiet --allow-empty -m first 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && pass "validator REJECT: commit not created (non-zero)" || fail "validator REJECT: commit not created (non-zero)" "exit $rc: $out"
git -C "$repo" rev-parse HEAD >/dev/null 2>&1 && fail "validator REJECT: no commit created" "HEAD exists" || pass "validator REJECT: no commit created"
[[ "$out" == *"custom validator rejection text"* ]] && pass "validator REJECT: validator stderr reached the user" || fail "validator REJECT: validator stderr reached the user" "$out"
teardown_world

# ============================================================ 5: commit-msg, stub validator exits 0, no repo hook -> commit created
setup_world
repo="$WORLD/repo5"; git init --quiet -b main "$repo"
out="$(git_c "$repo" commit --quiet --allow-empty -m first 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && pass "validator PASS, no repo hook: commit created" || fail "validator PASS, no repo hook: commit created" "exit $rc: $out"
git -C "$repo" rev-parse HEAD >/dev/null 2>&1 && pass "validator PASS, no repo hook: HEAD exists" || fail "validator PASS, no repo hook: HEAD exists" "$out"
teardown_world

# ============================================================ 6a: validator missing entirely -> rejected, "cannot execute", remedy named
setup_world
repo="$WORLD/repo6a"; git init --quiet -b main "$repo"
rm -f "$GCA_ROOT/validate"
out="$(git_c "$repo" commit --quiet --allow-empty -m first 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && pass "validator missing: commit rejected" || fail "validator missing: commit rejected" "exit $rc: $out"
[[ "$out" == *"cannot execute"* ]] && pass "validator missing: names what it could not run" || fail "validator missing: names what it could not run" "$out"
[[ "$out" == *"--no-verify"* && "$out" == *"rebuild"* ]] && pass "validator missing: remedy names rebuild and --no-verify" || fail "validator missing: remedy names rebuild and --no-verify" "$out"
git -C "$repo" rev-parse HEAD >/dev/null 2>&1 && fail "validator missing: no commit created" "HEAD exists" || pass "validator missing: no commit created"
teardown_world

# ============================================================ 6b: validator present but not executable -> same fail-closed behavior
setup_world
repo="$WORLD/repo6b"; git init --quiet -b main "$repo"
chmod -x "$GCA_ROOT/validate"
out="$(git_c "$repo" commit --quiet --allow-empty -m first 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && pass "validator not executable: commit rejected" || fail "validator not executable: commit rejected" "exit $rc: $out"
[[ "$out" == *"cannot execute"* ]] && pass "validator not executable: names what it could not run" || fail "validator not executable: names what it could not run" "$out"
[[ "$out" == *"--no-verify"* && "$out" == *"rebuild"* ]] && pass "validator not executable: remedy names rebuild and --no-verify" || fail "validator not executable: remedy names rebuild and --no-verify" "$out"
teardown_world

# ============================================================ 7: non-commit-msg hooks never invoke the validator
setup_world
repo="$WORLD/repo7"; git init --quiet -b main "$repo"
# The repo's own pre-commit asserts, at the moment it runs, that the validator
# has not been invoked yet -- this observes ordering/isolation directly rather
# than inferring it, and would fail if dispatch ever called the validator on
# the pre-commit path or called it before chaining to pre-commit.
write_hook "$repo/.git" pre-commit "if [ -s \"\$VALIDATOR_LOG\" ]; then touch '$WORLD/precommit-saw-validator'; exit 1; fi; touch '$WORLD/precommit-ok'"
printf 'staged\n' > "$repo/f"
git -C "$repo" add f
out="$(git_c "$repo" commit --quiet -m first 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && pass "non-commit-msg hooks: commit still succeeds" || fail "non-commit-msg hooks: commit still succeeds" "exit $rc: $out"
[ -f "$WORLD/precommit-ok" ] && pass "non-commit-msg hooks: pre-commit ran with an empty validator log" || fail "non-commit-msg hooks: pre-commit ran with an empty validator log" "$out"
[ ! -f "$WORLD/precommit-saw-validator" ] && pass "non-commit-msg hooks: validator was not invoked before pre-commit" || fail "non-commit-msg hooks: validator was not invoked before pre-commit" "validator log had entries at pre-commit time"
# Direct invocation of representative non-commit-msg hook names, simulating
# how git itself would exec them (argv[0] = the farm's symlink path).
: > "$VALIDATOR_LOG"
( cd "$repo" && "$GATE_DIR/hooks/pre-push" )
( cd "$repo" && "$GATE_DIR/hooks/post-commit" )
[ "$(validator_call_count)" = "0" ] && pass "non-commit-msg hooks: direct invocation never touches the validator" || fail "non-commit-msg hooks: direct invocation never touches the validator" "log: $(cat "$VALIDATOR_LOG")"
teardown_world

# ============================================================ 8: git commit --no-verify with a rejecting stub -> commit created (bypass)
setup_world
repo="$WORLD/repo8"; git init --quiet -b main "$repo"
printf '1\n' > "$VALIDATOR_RC"
out="$(git_c "$repo" commit --quiet --no-verify --allow-empty -m first 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && pass "--no-verify: commit created despite rejecting stub" || fail "--no-verify: commit created despite rejecting stub" "exit $rc: $out"
git -C "$repo" rev-parse HEAD >/dev/null 2>&1 && pass "--no-verify: HEAD exists" || fail "--no-verify: HEAD exists" "$out"
[ "$(validator_call_count)" = "0" ] && pass "--no-verify: validator never invoked (git skips the hook entirely)" || fail "--no-verify: validator never invoked" "log: $(cat "$VALIDATOR_LOG")"
teardown_world

# ============================================================ 9: linked worktree -- repo hook in main .git/hooks runs (--git-common-dir)
setup_world
repo="$WORLD/repo9"; git init --quiet -b main "$repo"
git_c "$repo" commit --quiet --allow-empty -m init
wt="$WORLD/wt9"
git -C "$repo" worktree add --quiet "$wt" -b feature9 >/dev/null 2>&1
write_hook "$repo/.git" pre-commit "touch '$WORLD/wt-marker'"
out="$(git_c "$wt" commit --quiet --allow-empty -m "in worktree" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && pass "linked worktree: commit succeeds" || fail "linked worktree: commit succeeds" "exit $rc: $out"
[ -f "$WORLD/wt-marker" ] && pass "linked worktree: main .git/hooks pre-commit runs (--git-common-dir)" || fail "linked worktree: main .git/hooks pre-commit runs (--git-common-dir)" "$out"
teardown_world

# ============================================================ 10: push-to-checkout, updateInstead, clean target, no repo hook -> accepted
setup_world
target="$WORLD/target10"; git init --quiet -b main "$target"
printf 'v1\n' > "$target/f"; git_c "$target" add f >/dev/null; git_c "$target" commit --quiet -m init
git -C "$target" config receive.denyCurrentBranch updateInstead
pusher="$WORLD/pusher10"; git clone --quiet "$target" "$pusher" >/dev/null 2>&1
printf 'v2\n' > "$pusher/f"; git_c "$pusher" add f >/dev/null; git_c "$pusher" commit --quiet -m second
new_tip="$(git -C "$pusher" rev-parse HEAD)"
out="$(git -C "$pusher" push --quiet origin main 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && pass "push-to-checkout clean: push accepted" || fail "push-to-checkout clean: push accepted" "exit $rc: $out"
[ "$(git -C "$target" rev-parse main)" = "$new_tip" ] && pass "push-to-checkout clean: target ref equals pushed tip" || fail "push-to-checkout clean: target ref equals pushed tip" "$out"
[ "$(cat "$target/f")" = "v2" ] && pass "push-to-checkout clean: target worktree equals pushed tip" || fail "push-to-checkout clean: target worktree equals pushed tip" "content: $(cat "$target/f")"
status="$(git -C "$target" status --porcelain)"
[ -z "$status" ] && pass "push-to-checkout clean: target status --porcelain empty" || fail "push-to-checkout clean: target status --porcelain empty" "status: $status"
teardown_world

# ============================================================ 11: push-to-checkout, dirty target -> refused, ref unmoved, local edit intact
setup_world
target="$WORLD/target11"; git init --quiet -b main "$target"
printf 'v1\n' > "$target/f"; git_c "$target" add f >/dev/null; git_c "$target" commit --quiet -m init
git -C "$target" config receive.denyCurrentBranch updateInstead
old_tip="$(git -C "$target" rev-parse main)"
pusher="$WORLD/pusher11"; git clone --quiet "$target" "$pusher" >/dev/null 2>&1
printf 'v2\n' > "$pusher/f"; git_c "$pusher" add f >/dev/null; git_c "$pusher" commit --quiet -m second
printf 'dirty-local-edit\n' > "$target/f"
out="$(git -C "$pusher" push --quiet origin main 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && pass "push-to-checkout dirty: push refused" || fail "push-to-checkout dirty: push refused" "exit $rc: $out"
[ "$(git -C "$target" rev-parse main)" = "$old_tip" ] && pass "push-to-checkout dirty: target ref unmoved" || fail "push-to-checkout dirty: target ref unmoved" "$out"
[ "$(cat "$target/f")" = "dirty-local-edit" ] && pass "push-to-checkout dirty: local edit intact" || fail "push-to-checkout dirty: local edit intact" "content: $(cat "$target/f")"
teardown_world

# ============================================================ 12: push-to-checkout, repo hook present -> repo hook runs (marker)
setup_world
target="$WORLD/target12"; git init --quiet -b main "$target"
printf 'v1\n' > "$target/f"; git_c "$target" add f >/dev/null; git_c "$target" commit --quiet -m init
git -C "$target" config receive.denyCurrentBranch updateInstead
write_hook "$target/.git" push-to-checkout "touch '$WORLD/p2c-marker'; exit 0"
pusher="$WORLD/pusher12"; git clone --quiet "$target" "$pusher" >/dev/null 2>&1
printf 'v2\n' > "$pusher/f"; git_c "$pusher" add f >/dev/null; git_c "$pusher" commit --quiet -m second
new_tip="$(git -C "$pusher" rev-parse HEAD)"
out="$(git -C "$pusher" push --quiet origin main 2>&1)"; rc=$?
[ -f "$WORLD/p2c-marker" ] && pass "push-to-checkout repo hook: repo hook runs (marker)" || fail "push-to-checkout repo hook: repo hook runs (marker)" "$out"
[ "$rc" -eq 0 ] && pass "push-to-checkout repo hook: push accepted (hook exited 0)" || fail "push-to-checkout repo hook: push accepted (hook exited 0)" "exit $rc: $out"
[ "$(git -C "$target" rev-parse main)" = "$new_tip" ] && pass "push-to-checkout repo hook: ref moved to pushed tip" || fail "push-to-checkout repo hook: ref moved to pushed tip" "$out"
teardown_world

# ============================================================ 13: proc-receive, matched ref, no repo hook -> push rejected (mirrors absent hook)
setup_world
target="$WORLD/target13"; git init --quiet -b main "$target"
git_c "$target" commit --quiet --allow-empty -m init
# receive.procReceiveRefs matches by plain string prefix, not glob -- verified
# empirically: a trailing '*' never matches and the hook is never invoked.
git -C "$target" config receive.procReceiveRefs 'refs/heads/special/'
pusher="$WORLD/pusher13"; git clone --quiet "$target" "$pusher" >/dev/null 2>&1
out="$(git -C "$pusher" push --quiet origin "HEAD:refs/heads/special/foo" 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && pass "proc-receive absent: push rejected" || fail "proc-receive absent: push rejected" "exit $rc: $out"
git -C "$target" rev-parse refs/heads/special/foo >/dev/null 2>&1 && fail "proc-receive absent: matched ref not created" "ref exists" || pass "proc-receive absent: matched ref not created"
teardown_world

printf '\n%d passed, %d failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
