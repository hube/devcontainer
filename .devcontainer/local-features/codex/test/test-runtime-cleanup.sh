#!/usr/bin/env bash
set -euo pipefail

test_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
runtime_test="$test_dir/test-runtime.sh"
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

stub_dir="$test_root/stubs"
mkdir -p "$stub_dir"

cat >"$stub_dir/docker" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$CLEANUP_TEST_LOG/docker-args"
case "$1 $2" in
  "volume rm")
    if [[ "${VOLUME_RM_WORLD:-good}" == "fail" ]]; then
      printf 'volume removal exploded\r\nvolume detail\n' >&2
      exit 31
    fi
    ;;
  "image rm")
    if [[ "${IMAGE_RM_WORLD:-good}" == "fail" ]]; then
      printf 'image removal exploded\r\nimage detail\n' >&2
      exit 37
    fi
    ;;
esac
EOF
chmod +x "$stub_dir/docker"

run_world() {
  local name="$1"
  shift
  local world_dir="$test_root/$name"
  mkdir -p "$world_dir/log"
  : >"$world_dir/build.log"
  set +e
  env PATH="$stub_dir:/usr/bin:/bin" \
    CLEANUP_TEST_LOG="$world_dir/log" \
    CODEX_RUNTIME_CLEANUP_TEST=1 \
    CODEX_RUNTIME_CLEANUP_TEST_BUILD_LOG="$world_dir/build.log" \
    CODEX_RUNTIME_CLEANUP_TEST_VOLUME="runtime-volume" \
    CODEX_RUNTIME_CLEANUP_TEST_IMAGE="runtime-image:test" \
    "$@" bash "$runtime_test" >"$world_dir/stdout" 2>"$world_dir/stderr"
  WORLD_STATUS=$?
  set -e
  WORLD_STDOUT="$(<"$world_dir/stdout")"
  WORLD_STDERR="$(<"$world_dir/stderr")"
  WORLD_DIR="$world_dir"
}

run_world cleanup-success CODEX_RUNTIME_CLEANUP_TEST_STATUS=0
[[ $WORLD_STATUS -eq 0 ]] || fail "successful cleanup changed status to $WORLD_STATUS: $WORLD_STDERR"
[[ ! -e "$WORLD_DIR/build.log" ]] || fail "successful cleanup left the build log"
mapfile -t docker_args <"$WORLD_DIR/log/docker-args"
[[ "${docker_args[*]}" == "volume rm -f runtime-volume image rm -f runtime-image:test" ]] || fail "successful cleanup did not attempt volume then image cleanup: ${docker_args[*]}"
printf '%s\n' 'PASS: successful cleanup removes every resource in order'

run_world status-preservation CODEX_RUNTIME_CLEANUP_TEST_STATUS=17
[[ $WORLD_STATUS -eq 17 ]] || fail "successful cleanup did not preserve original status 17: got $WORLD_STATUS"
printf '%s\n' 'PASS: successful cleanup preserves the original nonzero status'

run_world volume-failure CODEX_RUNTIME_CLEANUP_TEST_STATUS=0 VOLUME_RM_WORLD=fail
[[ $WORLD_STATUS -ne 0 ]] || fail "volume cleanup failure unexpectedly succeeded"
assert_ordered "$WORLD_STDERR" \
  "wrapper volume 'runtime-volume' could not be removed" \
  "The test volume remains on the Docker engine" \
  "Remove it with 'docker volume rm -f runtime-volume' after resolving Docker access" \
  "docker volume rm said: volume removal exploded\\r\\nvolume detail"
assert_contains "$(<"$WORLD_DIR/log/docker-args")" "image rm -f runtime-image:test" "image cleanup after volume failure"
printf '%s\n' 'PASS: volume cleanup failure fails the test and does not skip image cleanup'

run_world image-failure CODEX_RUNTIME_CLEANUP_TEST_STATUS=0 IMAGE_RM_WORLD=fail
[[ $WORLD_STATUS -ne 0 ]] || fail "image cleanup failure unexpectedly succeeded"
assert_ordered "$WORLD_STDERR" \
  "temporary image 'runtime-image:test' could not be removed" \
  "The temporary image remains on the Docker engine" \
  "Remove it with 'docker image rm -f runtime-image:test' after resolving Docker access" \
  "docker image rm said: image removal exploded\\r\\nimage detail"
printf '%s\n' 'PASS: image cleanup failure fails the test with relayed Docker output'

run_world both-failures CODEX_RUNTIME_CLEANUP_TEST_STATUS=0 VOLUME_RM_WORLD=fail IMAGE_RM_WORLD=fail
[[ $WORLD_STATUS -ne 0 ]] || fail "combined cleanup failures unexpectedly succeeded"
assert_ordered "$WORLD_STDERR" \
  "docker volume rm said: volume removal exploded\\r\\nvolume detail" \
  "docker image rm said: image removal exploded\\r\\nimage detail"
[[ "$(printf '%s\n' "$WORLD_STDERR" | grep -c 'Codex runtime test cleanup failed')" -eq 2 ]] || fail "combined cleanup did not report exactly two diagnostics: $WORLD_STDERR"
printf '%s\n' 'PASS: volume and image cleanup failures are both diagnosed in order'
