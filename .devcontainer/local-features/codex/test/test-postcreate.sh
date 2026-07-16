#!/usr/bin/env bash
set -euo pipefail

feature_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
hook="$feature_dir/bin/devcontainer-feature/codex/postCreateScript.sh"
test_root="$(mktemp -d)"
trap '/bin/rm -rf "$test_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local description="$3"
  [[ "$haystack" == *"$needle"* ]] || fail "$description: expected '$needle' in '$haystack'"
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local description="$3"
  [[ "$haystack" != *"$needle"* ]] || fail "$description: did not expect '$needle' in '$haystack'"
}

assert_ordered() {
  local text="$1"
  shift
  local remainder="$text"
  local needle
  for needle in "$@"; do
    [[ "$remainder" == *"$needle"* ]] || fail "ordered diagnostic: expected '$needle' after preceding fields in '$text'"
    remainder="${remainder#*"$needle"}"
  done
}

assert_physical_line_count() {
  local text="$1"
  local expected="$2"
  local description="$3"
  local actual
  actual="$(printf '%s\n' "$text" | awk 'END { print NR }')"
  [[ "$actual" -eq "$expected" ]] || fail "$description: expected $expected physical lines, got $actual in '$text'"
}

stub_dir="$test_root/stubs"
mkdir -p "$stub_dir"

cat >"$stub_dir/stat" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$TEST_LOG/stat-args"
if [[ "${STAT_WORLD:-good}" == "fail" ]]; then
  printf '%s\n' 'stat exploded' >&2
  exit 19
fi
if [[ "${STAT_WORLD:-good}" == "multiline-fail" ]]; then
  printf 'stat exploded\r\nstat detail\n' >&2
  exit 19
fi
printf '%s\n' "${STAT_METADATA:-root:root 4755}"
EOF

cat >"$stub_dir/mktemp" <<'EOF'
#!/usr/bin/env bash
if [[ "${MKTEMP_WORLD:-good}" == "multiline-fail" ]]; then
  printf 'mktemp exploded\r\nmktemp detail\n' >&2
  exit 17
fi
exec /usr/bin/mktemp "$@"
EOF

cat >"$stub_dir/timeout" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$TEST_LOG/timeout-args"
[[ "$1" == "30s" ]] || exit 97
shift
exec "$@"
EOF

cat >"$stub_dir/codex" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$TEST_LOG/codex-args"
if [[ "${CODEX_WORLD:-good}" == "fail" ]]; then
  printf '%s\n' 'codex exploded' >&2
  exit 23
fi
if [[ "${CODEX_WORLD:-good}" == "multiline-fail" ]]; then
  printf 'codex exploded\r\ncodex detail\n' >&2
  exit 23
fi

workdir=""
while (($#)); do
  if [[ "$1" == "-C" ]]; then
    workdir="$2"
    break
  fi
  shift
done
[[ -n "$workdir" ]] || exit 98
printf '%s\n' "$workdir" >"$TEST_LOG/workdir"
if [[ "${CODEX_WORLD:-good}" == "bad-marker" ]]; then
  printf '%s\n' codex-sandbox-wrong >"$workdir/codex-sandbox-marker"
else
  printf '%s\n' codex-sandbox-ok >"$workdir/codex-sandbox-marker"
fi
if [[ "${CODEX_WORLD:-good}" == "banner" ]]; then
  printf '%s\n' 'Codex sandbox notice: using Bubblewrap'
fi
printf '%s\n' codex-sandbox-ok
EOF

cat >"$stub_dir/rm" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$TEST_LOG/rm-args"
if [[ "${RM_WORLD:-good}" == "multiline-fail" ]]; then
  printf 'rm exploded\r\nrm detail\n' >&2
  exit 29
fi
exec /bin/rm "$@"
EOF

chmod +x "$stub_dir/stat" "$stub_dir/mktemp" "$stub_dir/timeout" "$stub_dir/codex" "$stub_dir/rm"

run_world() {
  local name="$1"
  shift
  local world_dir="$test_root/$name"
  mkdir -p "$world_dir/log"
  set +e
  env PATH="$stub_dir:/usr/bin:/bin" TEST_LOG="$world_dir/log" "$@" \
    bash "$hook" >"$world_dir/stdout" 2>"$world_dir/stderr"
  WORLD_STATUS=$?
  set -e
  WORLD_STDOUT="$(<"$world_dir/stdout")"
  WORLD_STDERR="$(<"$world_dir/stderr")"
  WORLD_DIR="$world_dir"
}

run_world success
[[ $WORLD_STATUS -eq 0 ]] || fail "success world exited $WORLD_STATUS: $WORLD_STDERR"
[[ "$(<"$WORLD_DIR/log/stat-args")" == "-c %U:%G %a /usr/bin/bwrap" ]] || fail "stat arguments were not exact"
success_workdir="$(<"$WORLD_DIR/log/workdir")"
mapfile -t codex_args <"$WORLD_DIR/log/codex-args"
expected_codex_args=(
  sandbox -P :workspace -C "$success_workdir" bash -c
  "printf '%s\\n' codex-sandbox-ok > codex-sandbox-marker && cat codex-sandbox-marker"
)
[[ "${codex_args[*]}" == "${expected_codex_args[*]}" && ${#codex_args[@]} -eq ${#expected_codex_args[@]} ]] || fail "Codex arguments were not exact"
mapfile -t timeout_args <"$WORLD_DIR/log/timeout-args"
expected_timeout_args=(30s codex "${expected_codex_args[@]}")
[[ "${timeout_args[*]}" == "${expected_timeout_args[*]}" && ${#timeout_args[@]} -eq ${#expected_timeout_args[@]} ]] || fail "timeout arguments were not exact"
[[ ! -e "$success_workdir" ]] || fail "temporary workdir was not cleaned up"
[[ "$(<"$WORLD_DIR/log/rm-args")" == "-rf $success_workdir" ]] || fail "cleanup did not remove the temporary workdir"
assert_not_contains "$WORLD_STDERR" "failed" "success diagnostics"
printf '%s\n' 'PASS: valid metadata and Codex marker readback succeed with exact arguments and cleanup'

run_world banner-success CODEX_WORLD=banner
[[ $WORLD_STATUS -eq 0 ]] || fail "benign banner world exited $WORLD_STATUS: $WORLD_STDERR"
printf '%s\n' 'PASS: an exact sentinel output line succeeds alongside a benign Codex banner'

run_world bad-metadata STAT_METADATA="root:root 0755"
[[ $WORLD_STATUS -ne 0 ]] || fail "bad metadata world unexpectedly succeeded"
assert_ordered "$WORLD_STDERR" \
  "metadata was 'root:root 0755', expected 'root:root 4755'" \
  "Codex sandbox startup is unsafe" \
  "Restore /usr/bin/bwrap to root:root with mode 4755, then rerun the hook" \
  "stat said: root:root 0755"
[[ -s "$WORLD_DIR/log/codex-args" ]] || fail "Codex probe did not run after bad metadata"
printf '%s\n' 'PASS: invalid Bubblewrap metadata fails after continuing through the Codex probe'

run_world stat-failure STAT_WORLD=fail
[[ $WORLD_STATUS -ne 0 ]] || fail "stat failure world unexpectedly succeeded"
assert_ordered "$WORLD_STDERR" \
  "Bubblewrap metadata could not be read" \
  "Codex sandbox startup cannot be verified" \
  "Ensure /usr/bin/bwrap exists and GNU stat can read it, then rerun the hook" \
  "stat said: stat exploded"
[[ -s "$WORLD_DIR/log/codex-args" ]] || fail "Codex probe did not run after stat failure"
printf '%s\n' 'PASS: stat failure is wrapped and does not skip the Codex probe'

run_world multiline-stat-failure STAT_WORLD=multiline-fail
[[ $WORLD_STATUS -ne 0 ]] || fail "multiline stat failure world unexpectedly succeeded"
assert_ordered "$WORLD_STDERR" \
  "Codex Bubblewrap health check failed because Bubblewrap metadata could not be read" \
  "stat said: stat exploded\\r\\nstat detail"
assert_physical_line_count "$WORLD_STDERR" 1 "multiline stat wrapper"
printf '%s\n' 'PASS: multiline stat output is preserved in one wrapper-added diagnostic line'

run_world multiline-mktemp-failure MKTEMP_WORLD=multiline-fail
[[ $WORLD_STATUS -ne 0 ]] || fail "multiline mktemp failure world unexpectedly succeeded"
assert_ordered "$WORLD_STDERR" \
  "Codex sandbox health check failed because a temporary workspace could not be created" \
  "mktemp said: mktemp exploded\\r\\nmktemp detail"
assert_physical_line_count "$WORLD_STDERR" 1 "multiline mktemp wrapper"
printf '%s\n' 'PASS: multiline mktemp output is preserved in one wrapper-added diagnostic line'

run_world codex-failure CODEX_WORLD=fail
[[ $WORLD_STATUS -ne 0 ]] || fail "Codex failure world unexpectedly succeeded"
assert_ordered "$WORLD_STDERR" \
  "Codex sandbox probe exited with status 23" \
  "Codex sandbox availability cannot be verified" \
  "Ensure Codex and GNU timeout are installed and sandboxing can create files in the workspace, then rerun the hook" \
  "codex sandbox said: codex exploded"
assert_not_contains "$WORLD_STDERR" "Bubblewrap metadata could not be read" "independent Codex failure"
printf '%s\n' 'PASS: Codex failure is wrapped with ordered problem, consequence, remedy, and output'

run_world multiline-codex-failure CODEX_WORLD=multiline-fail
[[ $WORLD_STATUS -ne 0 ]] || fail "multiline Codex failure world unexpectedly succeeded"
assert_ordered "$WORLD_STDERR" \
  "Codex sandbox health check failed because the Codex sandbox probe exited with status 23" \
  "codex sandbox said: codex exploded\\r\\ncodex detail"
assert_physical_line_count "$WORLD_STDERR" 1 "multiline Codex wrapper"
printf '%s\n' 'PASS: multiline Codex output is preserved in one wrapper-added diagnostic line'

run_world marker-failure CODEX_WORLD=bad-marker
[[ $WORLD_STATUS -ne 0 ]] || fail "marker mismatch world unexpectedly succeeded"
assert_ordered "$WORLD_STDERR" \
  "Codex sandbox probe did not create and read codex-sandbox-marker" \
  "Codex sandbox availability cannot be verified" \
  "Ensure Codex and GNU timeout are installed and sandboxing can create files in the workspace, then rerun the hook" \
  "codex sandbox said: codex-sandbox-ok"
printf '%s\n' 'PASS: marker contents must match the Codex sandbox sentinel'

run_world combined-failure STAT_WORLD=fail CODEX_WORLD=fail
[[ $WORLD_STATUS -ne 0 ]] || fail "combined failure world unexpectedly succeeded"
assert_ordered "$WORLD_STDERR" \
  "Bubblewrap metadata could not be read" \
  "stat said: stat exploded" \
  "Codex sandbox probe exited with status 23" \
  "codex sandbox said: codex exploded"
[[ "$(printf '%s\n' "$WORLD_STDERR" | grep -c 'health check failed')" -eq 2 ]] || fail "combined failure did not aggregate exactly two diagnostics: $WORLD_STDERR"
printf '%s\n' 'PASS: simultaneous metadata and Codex failures are aggregated in stable order'

run_world combined-multiline-failure STAT_WORLD=multiline-fail CODEX_WORLD=multiline-fail
[[ $WORLD_STATUS -ne 0 ]] || fail "combined multiline failure world unexpectedly succeeded"
assert_ordered "$WORLD_STDERR" \
  "stat said: stat exploded\\r\\nstat detail" \
  "codex sandbox said: codex exploded\\r\\ncodex detail"
assert_physical_line_count "$WORLD_STDERR" 2 "combined multiline wrappers"
printf '%s\n' 'PASS: each simultaneous multiline failure occupies one physical diagnostic line'

run_world cleanup-failure RM_WORLD=multiline-fail
[[ $WORLD_STATUS -ne 0 ]] || fail "cleanup failure world unexpectedly succeeded"
assert_ordered "$WORLD_STDERR" \
  "Codex sandbox health check cleanup failed because the temporary workspace" \
  "Codex sandbox health cannot be reported as successful" \
  "Remove the temporary workspace after restoring filesystem access, then rerun the hook" \
  "rm said: rm exploded\\r\\nrm detail"
assert_physical_line_count "$WORLD_STDERR" 1 "cleanup failure wrapper"
[[ "$(printf '%s\n' "$WORLD_STDERR" | grep -c 'health check.*failed')" -eq 1 ]] || fail "cleanup failure did not produce exactly one diagnostic: $WORLD_STDERR"
printf '%s\n' 'PASS: cleanup failure makes an otherwise healthy hook fail with relayed rm output'

run_world combined-cleanup-failure STAT_WORLD=multiline-fail CODEX_WORLD=multiline-fail RM_WORLD=multiline-fail
[[ $WORLD_STATUS -ne 0 ]] || fail "combined cleanup failure world unexpectedly succeeded"
assert_ordered "$WORLD_STDERR" \
  "stat said: stat exploded\\r\\nstat detail" \
  "codex sandbox said: codex exploded\\r\\ncodex detail" \
  "rm said: rm exploded\\r\\nrm detail"
assert_physical_line_count "$WORLD_STDERR" 3 "combined metadata, Codex, and cleanup wrappers"
[[ "$(printf '%s\n' "$WORLD_STDERR" | grep -c 'health check.*failed')" -eq 3 ]] || fail "combined cleanup failure did not aggregate exactly three diagnostics: $WORLD_STDERR"
printf '%s\n' 'PASS: metadata, Codex, and cleanup failures aggregate once each in stable order'
