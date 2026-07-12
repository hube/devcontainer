#!/usr/bin/env bash
# Two kinds of assertion, because either alone is misleading:
#   1. structural  -- the committed JSON says what we think it says
#   2. behavioural -- a real container under this profile can actually run bwrap
# The behavioural half reproduces issue #36 under the stock profile first, so a
# passing result cannot come from bwrap silently succeeding for other reasons.
set -uo pipefail

PROFILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/seccomp/userns.json"
GENERATED_SHA256="d563d512691ae8f2d437bfa7a9e77ac7d8c8d4a785277f8234bd688f4857ab86"
passed=0
failed=0

pass() { printf 'ok   %s\n' "$1"; passed=$((passed + 1)); }
fail() {
  printf 'FAIL %s\n     Problem: %s\n     Consequence: %s\n     Remedy: %s\n     %s\n' \
    "$1" "$2" "$3" "$4" "$5"
  failed=$((failed + 1))
}

assert_jq() {
  local label=$1 filter=$2 problem=$3 consequence=$4 remedy=$5 out rc
  out="$(jq -e "$filter" "$PROFILE" 2>&1)"; rc=$?
  if [[ $rc -eq 0 ]]; then
    pass "$label"
  else
    fail "$label" "$problem" "$consequence" "$remedy" \
      "jq said: ${out:-<no output>}"
  fi
}

# --- structural ---------------------------------------------------------
if [[ ! -f "$PROFILE" ]]; then
  out="$(ls -l "$PROFILE" 2>&1)"; rc=$?
  echo "FAIL profile: exists" >&2
  echo "     Problem: the seccomp profile is missing." >&2
  echo "     Consequence: structural and behavioural checks cannot run." >&2
  echo "     Remedy: generate the pinned profile, then rerun this test." >&2
  echo "     Profile check said: rc=$rc ${out:-<no output>}" >&2
  exit 1
fi

out="$(sha256sum "$PROFILE" 2>&1)"; rc=$?
actual_sha=${out%% *}
if [[ $rc -eq 0 && "$actual_sha" == "$GENERATED_SHA256" ]]; then
  pass "profile: matches the recorded generated SHA-256"
else
  fail "profile: matches the recorded generated SHA-256" \
    "the vendored generated profile does not match its recorded SHA-256." \
    "the profile may contain changes beyond the documented transformation." \
    "regenerate it from the pinned upstream file, review the transformation, and record the generated SHA-256." \
    "sha256sum said: ${out:-<no output>}"
fi

out="$(jq -e . "$PROFILE" 2>&1)"; rc=$?
if [[ $rc -eq 0 ]]; then
  pass "profile: is valid JSON"
else
  echo "FAIL profile: is valid JSON" >&2
  echo "     Problem: the seccomp profile is not valid JSON." >&2
  echo "     Consequence: Docker cannot load it and structural checks are unreliable." >&2
  echo "     Remedy: regenerate the profile from the pinned upstream file." >&2
  echo "     jq said: ${out:-<no output>}" >&2
  exit 1
fi

assert_jq "profile: default action still denies" \
  '.defaultAction == "SCMP_ACT_ERRNO"' \
  "the default action is not SCMP_ACT_ERRNO." \
  "syscalls absent from allow rules may no longer be denied." \
  "regenerate the profile and restore the upstream default action."

# An unconditional ALLOW rule: no capability gate, no arch gate, no arg filter.
unconditional='.syscalls[] | select(.action == "SCMP_ACT_ALLOW")
  | select(has("includes") | not) | select(has("excludes") | not)
  | select(has("args") | not) | .names[]'
for sc in mount umount2 setns unshare pivot_root; do
  assert_jq "profile: $sc is allowed unconditionally" \
    "[$unconditional] | index(\"$sc\") != null" \
    "$sc is absent from every ungated ALLOW rule." \
    "Bubblewrap may fail while constructing its user-namespace sandbox." \
    "regenerate the profile with the required unconditional allow rule."
done

# The CLONE_NEW* argument filter (mask 0x7e020000) must be gone from every
# clone rule, or CLONE_NEWUSER stays denied.
assert_jq "profile: no clone rule retains an argument filter" \
  '[.syscalls[] | select(.names | index("clone")) | select(has("args"))] | length == 0' \
  "a clone rule still has an argument filter." \
  "CLONE_NEWUSER remains denied, so Bubblewrap cannot create its sandbox." \
  "regenerate the profile with the clone argument filter removed."

# clone3 must STILL be ENOSYS without CAP_SYS_ADMIN. Ungating it would open a
# namespace path seccomp cannot filter; this asserts we did not do that.
assert_jq "profile: clone3 still returns ENOSYS so glibc falls back to clone" \
  '[.syscalls[]
    | select(.names | index("clone3"))
    | select(.action == "SCMP_ACT_ERRNO" and .errnoRet == 38)
    | select(.excludes.caps | index("CAP_SYS_ADMIN"))] | length == 1' \
  "the clone3 ENOSYS rule or its CAP_SYS_ADMIN exclusion was altered." \
  "an unfilterable namespace-creation path may be opened or fallback to clone may stop." \
  "restore the pinned upstream clone3 rule and rerun this test."

# --- behavioural --------------------------------------------------------
docker_out="$(docker info 2>&1)"; docker_rc=$?
if [[ $docker_rc -ne 0 ]]; then
  echo "WARNING: Docker is unavailable."
  echo "     Problem: docker info failed."
  echo "     Consequence: the two behavioural checks were skipped, so only profile structure was verified."
  echo "     Remedy: start Docker and rerun this test to verify runtime behaviour."
  echo "     docker info said: ${docker_out:-<no output>}"
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
    echo "     Problem: docker build failed." >&2
    echo "     Consequence: the bwrap checks cannot be trusted or run." >&2
    echo "     Remedy: fix the build error printed below, then rerun this test." >&2
    echo "     docker build said:" >&2
    cat "$BUILD_LOG" >&2
    exit 1
  fi

  # Retirement control: if the stock profile succeeds, reevaluate and remove the relaxations.
  out="$(docker run --rm "$IMAGE" bwrap --unshare-all --dev-bind / / true 2>&1)"; rc=$?
  if [[ $rc -ne 0 && "$out" == *"No permissions to create a new namespace"* ]]; then
    pass "control: stock profile reproduces issue #36"
  elif [[ $rc -eq 0 ]]; then
    fail "control: stock profile reproduces issue #36" \
      "Bubblewrap unexpectedly succeeded under Docker's stock seccomp profile." \
      "Docker's default profile may now be sufficient, so these relaxations may be obsolete." \
      "reevaluate and remove the vendored relaxations if the default policy now supports Bubblewrap." \
      "docker run said: rc=$rc ${out:-<no output>}"
  else
    fail "control: stock profile reproduces issue #36" \
      "Bubblewrap failed, but not with issue #36's namespace-permission diagnostic." \
      "the control failure may have an unrelated cause, so the treatment comparison is untrusted." \
      "fix the Docker or Bubblewrap error shown below, then rerun this test." \
      "docker run said: rc=$rc ${out:-<no output>}"
  fi

  # Treatment: the vendored profile must let bwrap start a sandbox and do work.
  out="$(docker run --rm --security-opt seccomp="$PROFILE" "$IMAGE" \
         bwrap --unshare-all --dev-bind / / --chdir /tmp sh -c 'echo ok > f && cat f' 2>&1)"; rc=$?
  if [[ $rc -eq 0 && "$out" == "ok" ]]; then
    pass "treatment: bwrap runs a sandboxed command under userns.json"
  elif [[ $rc -ne 0 ]]; then
    fail "treatment: bwrap runs a sandboxed command under userns.json" \
      "Bubblewrap failed under the vendored seccomp profile." \
      "the profile does not demonstrably enable Codex's patch sandbox." \
      "fix the Docker or Bubblewrap error shown below, then rerun this test." \
      "docker run said: rc=$rc ${out:-<no output>}"
  else
    fail "treatment: bwrap runs a sandboxed command under userns.json" \
      "the sandboxed command succeeded but returned unexpected output." \
      "the behavioural probe did not demonstrate the expected write/read result." \
      "inspect the command output shown below, restore the probe, and rerun this test." \
      "docker run said: rc=$rc ${out:-<no output>}"
  fi
fi

printf '\n%d passed, %d failed\n' "$passed" "$failed"
[[ $failed -eq 0 ]]
