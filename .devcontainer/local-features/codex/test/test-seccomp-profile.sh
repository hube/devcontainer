#!/usr/bin/env bash
# Two kinds of assertion, because either alone is misleading:
#   1. structural  -- the committed JSON says what we think it says
#   2. behavioural -- a real container under this profile can actually run bwrap
# The behavioural half reproduces issue #36 under the stock profile first, so a
# passing result cannot come from bwrap silently succeeding for other reasons.
set -uo pipefail

PROFILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/seccomp/userns.json"
passed=0
failed=0

pass() { printf 'ok   %s\n' "$1"; passed=$((passed + 1)); }
fail() { printf 'FAIL %s\n     %s\n' "$1" "$2"; failed=$((failed + 1)); }

# --- structural ---------------------------------------------------------
[[ -f "$PROFILE" ]] || { echo "missing profile: $PROFILE" >&2; exit 1; }
jq -e . "$PROFILE" >/dev/null 2>&1 && pass "profile: is valid JSON" \
  || fail "profile: is valid JSON" "jq could not parse it"

[[ "$(jq -r .defaultAction "$PROFILE")" == "SCMP_ACT_ERRNO" ]] \
  && pass "profile: default action still denies" \
  || fail "profile: default action still denies" "expected SCMP_ACT_ERRNO"

# An unconditional ALLOW rule: no capability gate, no arch gate, no arg filter.
unconditional='.syscalls[] | select(.action == "SCMP_ACT_ALLOW")
  | select(has("includes") | not) | select(has("excludes") | not)
  | select(has("args") | not) | .names[]'
for sc in mount umount2 setns unshare pivot_root; do
  if jq -e --arg sc "$sc" "[$unconditional] | index(\$sc)" "$PROFILE" >/dev/null; then
    pass "profile: $sc is allowed unconditionally"
  else
    fail "profile: $sc is allowed unconditionally" "not found in any ungated ALLOW rule"
  fi
done

# The CLONE_NEW* argument filter (mask 0x7e020000) must be gone from every
# clone rule, or CLONE_NEWUSER stays denied.
if jq -e '[.syscalls[] | select(.names | index("clone")) | select(has("args"))] | length == 0' \
     "$PROFILE" >/dev/null; then
  pass "profile: no clone rule retains an argument filter"
else
  fail "profile: no clone rule retains an argument filter" "a clone rule still has .args"
fi

# clone3 must STILL be ENOSYS without CAP_SYS_ADMIN. Ungating it would open a
# namespace path seccomp cannot filter; this asserts we did not do that.
if jq -e '[.syscalls[]
      | select(.names | index("clone3"))
      | select(.action == "SCMP_ACT_ERRNO" and .errnoRet == 38)
      | select(.excludes.caps | index("CAP_SYS_ADMIN"))] | length == 1' \
     "$PROFILE" >/dev/null; then
  pass "profile: clone3 still returns ENOSYS so glibc falls back to clone"
else
  fail "profile: clone3 still returns ENOSYS so glibc falls back to clone" \
       "the clone3 ERRNO rule was altered or removed"
fi

# --- behavioural --------------------------------------------------------
if ! docker info >/dev/null 2>&1; then
  printf '\nSKIP behavioural checks: docker is unavailable\n'
else
  BUILD_LOG="$(mktemp)"
  IMAGE="codex-bwrap-probe:test-$(basename "$BUILD_LOG")"
  cleanup_image() {
    docker image rm -f "$IMAGE" >/dev/null 2>&1 || true
    rm -f "$BUILD_LOG"
  }
  trap cleanup_image EXIT

  if ! docker build -t "$IMAGE" - >"$BUILD_LOG" 2>&1 <<'DOCKERFILE'
FROM ubuntu:rolling
RUN apt-get update && apt-get install -y bubblewrap && rm -rf /var/lib/apt/lists/*
DOCKERFILE
  then
    echo "FAIL behavioural setup: Docker could not build the probe image." >&2
    echo "     Consequence: the bwrap checks cannot be trusted or run." >&2
    echo "     Remedy: fix the build error printed below, then rerun this test." >&2
    echo "     docker build said:" >&2
    cat "$BUILD_LOG" >&2
    exit 1
  fi

  # Control: the stock profile must still fail, and fail for the reason #36 reports.
  out="$(docker run --rm "$IMAGE" bwrap --unshare-all --dev-bind / / true 2>&1)"; rc=$?
  [[ $rc -ne 0 && "$out" == *"No permissions to create a new namespace"* ]] \
    && pass "control: stock profile reproduces issue #36" \
    || fail "control: stock profile reproduces issue #36" "rc=$rc out=$out"

  # Treatment: the vendored profile must let bwrap start a sandbox and do work.
  out="$(docker run --rm --security-opt seccomp="$PROFILE" "$IMAGE" \
         bwrap --unshare-all --dev-bind / / --chdir /tmp sh -c 'echo ok > f && cat f' 2>&1)"; rc=$?
  [[ $rc -eq 0 && "$out" == "ok" ]] \
    && pass "treatment: bwrap runs a sandboxed command under userns.json" \
    || fail "treatment: bwrap runs a sandboxed command under userns.json" "rc=$rc out=$out"
fi

printf '\n%d passed, %d failed\n' "$passed" "$failed"
[[ $failed -eq 0 ]]
