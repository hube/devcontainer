#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
CONSUMER="$ROOT/.devcontainer/local-features/codex/test/test-image-consumer.sh"
TEST_ROOT="$(mktemp -d)"
trap '/bin/rm -rf "$TEST_ROOT"' EXIT

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

STUBS="$TEST_ROOT/stubs"
mkdir -p "$STUBS"

cat >"$STUBS/docker" <<'DOCKER'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$TEST_LOG/docker-args"
case "${1:-} ${2:-}" in
  "inspect "*)
    python3 - "$TEST_REPO_ROOT" "$TEST_HOME" <<'PY'
import json
import sys

repo, home = sys.argv[1:]
print(json.dumps([{"Mounts": [
    {"Type": "bind", "Destination": repo, "Source": repo},
    {"Type": "bind", "Destination": home + "/.ssh", "Source": home + "/.ssh"},
]}]))
PY
    ;;
  "info --format")
    printf '%s\n' 'Docker Desktop'
    ;;
  "ps -aq")
    label=""
    for argument in "$@"; do
      case "$argument" in
        label=codex.image-consumer=*) label="${argument#label=codex.image-consumer=}" ;;
      esac
    done
    [[ -n "$label" ]]
    python3 - "$label" >"$TEST_STATE/volume" <<'PY'
import hashlib
import json
import sys

canonical = json.dumps({"codex.image-consumer": sys.argv[1]}, separators=(",", ":"), sort_keys=True)
number = int.from_bytes(hashlib.sha256(canonical.encode()).digest(), "big")
alphabet = "0123456789abcdefghijklmnopqrstuv"
encoded = ""
while number:
    number, remainder = divmod(number, 32)
    encoded = alphabet[remainder] + encoded
print("fixture-volume-" + encoded.rjust(52, "0"))
PY
    printf '%s\n' 'fixture-container'
    ;;
  "volume ls")
    [[ -s "$TEST_STATE/volume" ]] && cat "$TEST_STATE/volume"
    ;;
  "rm -f")
    ;;
  "volume rm")
    ;;
  *)
    printf 'unexpected docker arguments: %s\n' "$*" >&2
    exit 97
    ;;
esac
DOCKER
chmod +x "$STUBS/docker"

cat >"$STUBS/npx" <<'NPX'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$TEST_LOG/npx-args"
case "${3:-}" in
  up)
    printf '%s\n' '{"containerId":"fixture-container"}'
    ;;
  exec)
    status="${NPM_EXEC_STATUS:-0}"
    if [[ "$status" -ne 0 ]]; then
      printf '%s\n' 'stub exec failed' >&2
      exit "$status"
    fi
    printf '%s\n' 'stub exec succeeded'
    ;;
  *)
    printf 'unexpected npx arguments: %s\n' "$*" >&2
    exit 98
    ;;
esac
NPX
chmod +x "$STUBS/npx"

run_world() {
  local name="$1"
  shift
  local world="$TEST_ROOT/$name"
  mkdir -p "$world/home/.ssh" "$world/npm-cache" "$world/state" "$world/log"
  : >"$world/log/docker-args"
  : >"$world/log/npx-args"
  set +e
  env PATH="$STUBS:/usr/bin:/bin" \
    HOME="$world/home" \
    npm_config_cache="$world/npm-cache" \
    TEST_REPO_ROOT="$ROOT" \
    TEST_HOME="$world/home" \
    TEST_STATE="$world/state" \
    TEST_LOG="$world/log" \
    "$@" bash "$CONSUMER" fixture-image:test \
    >"$world/stdout" 2>"$world/stderr"
  WORLD_STATUS=$?
  set -e
  WORLD_STDOUT="$(<"$world/stdout")"
  WORLD_STDERR="$(<"$world/stderr")"
  WORLD="$world"
}

assert_cleanup_once() {
  local volume
  volume="$(<"$WORLD/state/volume")"
  [[ "$(grep -Fxc 'rm -f -v fixture-container' "$WORLD/log/docker-args")" -eq 1 ]] ||
    fail "fixture container was not removed exactly once: $(<"$WORLD/log/docker-args")"
  [[ "$(grep -Fxc "volume rm -f $volume" "$WORLD/log/docker-args")" -eq 1 ]] ||
    fail "fixture volume was not removed exactly once: $(<"$WORLD/log/docker-args")"
}

run_world success NPM_EXEC_STATUS=0
[[ $WORLD_STATUS -eq 0 ]] || fail "duplicate rediscovery changed successful status to $WORLD_STATUS: $WORLD_STDERR"
assert_contains "$WORLD_STDOUT" \
  "Image 'fixture-image:test': post-create health and sandboxed patch persistence were verified." \
  "published-image success output"
assert_cleanup_once
printf '%s\n' 'PASS: duplicate fixture rediscovery preserves successful cleanup status'

run_world failing-exec NPM_EXEC_STATUS=23
[[ $WORLD_STATUS -eq 23 ]] || fail "duplicate rediscovery replaced original status 23 with $WORLD_STATUS: $WORLD_STDERR"
assert_ordered "$WORLD_STDERR" \
  "Codex image-consumer sandboxed patch verification failed for image 'fixture-image:test'." \
  "The unrelated consumer did not prove that a tracked-file edit persists through Codex's sandbox." \
  "Correct the reported Git, Codex sandbox, or apply_patch failure and rerun the test." \
  "devcontainer exec said: stub exec failed"
assert_cleanup_once
printf '%s\n' 'PASS: successful cleanup preserves the original nonzero status'
