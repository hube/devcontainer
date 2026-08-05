#!/usr/bin/env bash
# Probes what the design records under *Verified Behavior* about Codex's inner
# bwrap sandbox: that the gate is visible to a command Codex launches there,
# and that when a commit can run it produces the gate's diagnosis on stderr.
# This cannot be answered from CI (no bwrap user-namespace support on the
# runner) or from a container where the gate has not been installed, so the
# guards below make this script a safe no-op in both places; it is meant to be
# run manually inside a rebuilt container (tracked in #51).
#
# Two assertions under two permission profiles, because no single profile can
# carry both:
#
#   1. VISIBILITY, under `-P :workspace` — the profile the Codex Feature's own
#      postCreateScript.sh launches. Every component the gate needs is readable
#      inside the sandbox and identical to what the host sees.
#   2. END-TO-END, under `-P :danger-full-access`. Codex bind-mounts every
#      `.git` directory read-only under `:workspace` and `:read-only` alike, so
#      `git commit` there cannot create `.git/index.lock` and no `commit-msg`
#      hook can run under either; `:danger-full-access` is the only built-in
#      profile where `.git` is writable. That is a Codex filesystem policy,
#      upstream of this Feature and nothing to do with the gate — so do NOT
#      "fix" this assertion back to `:workspace`. It would fail with
#      `Unable to create '.../.git/index.lock': Read-only file system`, which
#      says nothing about whether the gate works.
#
# This probe never writes or mounts its own spec, and never flips `mode`: it
# runs against whatever the live spec at the fixed /etc path already says, and
# skips unless that is `mode warn` — the only mode its fixture expectation is
# written for. When the rollout flips to `mode enforce`, extend the end-to-end
# assertion with the rejection expectation rather than deleting the guard.
set -uo pipefail

GCA_ROOT=/usr/local/share/git-commit-attribution
HOOKS_DIR="$GCA_ROOT/hooks"
VALIDATOR="$GCA_ROOT/validate"
SPEC=/etc/devcontainer/feature/git-commit-attribution/trailer-contract

if [[ ! -d "$HOOKS_DIR" ]]; then
  echo "skip: $HOOKS_DIR not present (gate not installed in this container)"
  exit 0
fi

if ! command -v codex >/dev/null 2>&1; then
  echo "skip: codex CLI not on PATH (Codex sandbox wrapper unavailable)"
  exit 0
fi

# Same health signal the Codex Feature's own postCreateScript.sh uses to
# decide whether its sandbox can start (local-features/codex/bin/
# devcontainer-feature/codex/postCreateScript.sh): system Bubblewrap must be
# root:root mode 4755, or `codex sandbox` cannot construct its inner sandbox.
bwrap_meta="$(stat -c '%U:%G %a' /usr/bin/bwrap 2>/dev/null)" || bwrap_meta=""
if [[ "$bwrap_meta" != "root:root 4755" ]]; then
  echo "skip: /usr/bin/bwrap missing or not root:root 4755 (Codex sandbox wrapper unavailable)"
  exit 0
fi

# The spec mount belongs to the consuming devcontainer.json, not to the
# Feature, so a gate-installed container can legitimately lack it; the
# Feature's own postStart script is what reports that. Skipping here keeps
# a consumer misconfiguration from surfacing as a gate failure.
if [[ ! -f "$SPEC" ]]; then
  echo "skip: $SPEC not present (consuming devcontainer.json does not declare the spec mount)"
  exit 0
fi

spec_mode="$(awk '$1 == "mode" { print $2; exit }' "$SPEC")"
if [[ "$spec_mode" != "warn" ]]; then
  echo "skip: live spec says 'mode ${spec_mode:-<unset>}', not 'mode warn' (this probe's fixture expects the warn-mode diagnosis)"
  exit 0
fi

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

git init --quiet -b main "$workdir" >/dev/null

fail() {
  echo "FAIL: $1" >&2
  shift
  printf '%s\n' "$@" >&2
  exit 1
}

# ---------------------------------------------------------------------------
# 1. Visibility under the profile Codex actually launches.
# ---------------------------------------------------------------------------

# Every expectation below is the host's own value, read here rather than
# hardcoded, so the assertion is "the sandbox sees what the host sees" and
# nothing in this script has to be updated when the validator is rebuilt.
host_hooks_origin="$(git config --show-origin --get core.hooksPath 2>&1 | tr '\t' ' ')"
host_commit_msg="$(readlink -f "$HOOKS_DIR/commit-msg" 2>&1)"
host_validator_sha="$(sha256sum "$VALIDATOR" 2>&1 | cut -d' ' -f1)"

# A component the host itself cannot read leaves an error string in the
# baseline, and the sandbox would report the same error string — so the
# comparison below would pass while proving nothing. Reject a baseline that is
# not a real value before comparing anything against it. The design's claim is
# also not merely that core.hooksPath has a value, but that it resolves from
# the system file install.sh writes, so the origin is checked, not just the
# path.
if [[ "$host_hooks_origin" != "file:/etc/gitconfig "* ]]; then
  fail "core.hooksPath does not resolve from /etc/gitconfig on the host, so there is no system-wide gate for this probe to look for inside the sandbox" \
    "host origin=$host_hooks_origin"
fi
if [[ ! -e "$host_commit_msg" ]]; then
  fail "the host cannot resolve $HOOKS_DIR/commit-msg to an existing file, so the sandbox has no hook to be compared against" \
    "host readlink=$host_commit_msg"
fi
if [[ ! "$host_validator_sha" =~ ^[0-9a-f]{64}$ ]]; then
  fail "the host cannot hash $VALIDATOR, so the sandbox has no validator bytes to be compared against" \
    "host sha256sum=$host_validator_sha"
fi

cat >"$workdir/visibility.sh" <<'VISIBILITY'
# Runs inside the sandbox. Emits one key=value line per component so each can
# be compared against the host's value independently, and so a component that
# is unreadable reports its own error text rather than an empty line.
set -u
hooks_dir=$1
validator=$2
spec=$3
printf 'hooks-origin=%s\n' "$(git config --show-origin --get core.hooksPath 2>&1 | tr '\t' ' ')"
printf 'commit-msg=%s\n' "$(readlink -f "$hooks_dir/commit-msg" 2>&1)"
printf 'validator-sha=%s\n' "$(sha256sum "$validator" 2>&1 | cut -d' ' -f1)"
printf 'spec-mode=%s\n' "$(awk '$1 == "mode" { print $2; exit }' "$spec" 2>&1)"
VISIBILITY

vis_err="$workdir/visibility.err"
vis="$(timeout 30s codex sandbox -P :workspace -C "$workdir" \
  bash visibility.sh "$HOOKS_DIR" "$VALIDATOR" "$SPEC" 2>"$vis_err")"
vis_rc=$?

if [[ "$vis_rc" -ne 0 ]]; then
  fail "codex sandbox -P :workspace could not run the visibility probe, so the gate's visibility is unknown (the sandbox itself failed to start; this is not a gate result)" \
    "exit=$vis_rc" "stdout=$vis" "stderr=$(cat "$vis_err" 2>/dev/null)"
fi

vis_get() { printf '%s\n' "$vis" | sed -n "s/^$1=//p"; }

expect_same() {
  local label=$1 expected=$2 actual
  actual="$(vis_get "$label")"
  if [[ "$actual" != "$expected" ]]; then
    fail "'$label' differs inside codex sandbox -P :workspace (the gate is not fully visible to sandboxed commands)" \
      "expected (host)=$expected" "actual (sandbox)=$actual" \
      "full probe output=$vis" "stderr=$(cat "$vis_err" 2>/dev/null)"
  fi
}

expect_same hooks-origin "$host_hooks_origin"
expect_same commit-msg "$host_commit_msg"
expect_same validator-sha "$host_validator_sha"
expect_same spec-mode "$spec_mode"

# ---------------------------------------------------------------------------
# 2. End-to-end diagnosis under the only profile with a writable .git.
# ---------------------------------------------------------------------------

# A violating-agent-style message: it triggers the gate (a Co-Authored-By
# naming a known agent address) but omits the Skills: trailer the design made
# mandatory, so mode warn should print a WARNING rather than reject. Drawn
# verbatim from test-integration.sh's FABRICATED_MSG fixture (hube/
# devcontainer#23), which exercises this exact violation against a real spec.
MSG='Report the finding.

Harness: Claude Code
Harness-Version: 2.1.205 (Claude Code)
Model: claude-haiku-4-5-20251001
Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>'

printf '%s' "$MSG" >"$workdir/msg.txt"

err_file="$workdir/commit.err"
# Mirrors the invocation shape postCreateScript.sh uses to launch a command
# inside Codex's inner sandbox (`codex sandbox -P <profile> -C <dir>
# <command>`), differing only in the profile, for the reason given in the
# header. Only the commit itself runs inside the sandbox; `git init` above is
# plain host git and not part of what this probes.
out="$(timeout 30s codex sandbox -P :danger-full-access -C "$workdir" \
  bash -c 'git -c user.email=t@t -c user.name=t commit --allow-empty -F msg.txt' \
  2>"$err_file")"
rc=$?
err="$(cat "$err_file" 2>/dev/null || true)"

# Verbatim from validate.ts's warn path (warningOutcome) for MSG's exact
# violation (missing the required 'Skills' trailer): the one diagnosis a true
# warn-mode pass can produce for this fixture. A missing/misplaced spec mount
# inside the sandbox instead emits a distinct rejection (e.g. "no spec at
# ...") with the same "git-commit-attribution:" prefix and a non-zero exit —
# matching only the prefix would call that a PASS too.
EXPECTED_DIAGNOSIS="git-commit-attribution: WARNING: commit message: missing the required trailer 'Skills'."

dump_and_fail() {
  fail "$1" "exit=$rc" "stdout=$out" "stderr=$err"
}

if [[ "$rc" -ne 0 ]]; then
  dump_and_fail "commit inside Codex sandbox exited non-zero (mode warn should have let it through)"
fi

if [[ "$err" != *"$EXPECTED_DIAGNOSIS"* ]]; then
  dump_and_fail "stderr did not contain the expected warn-mode diagnosis for the missing 'Skills' trailer (wrong or missing diagnosis)"
fi

if ! git -C "$workdir" rev-parse --verify HEAD >/dev/null 2>&1; then
  dump_and_fail "commit-msg hook exited 0 but no commit exists in $workdir"
fi

echo "PASS: gate visible inside codex sandbox -P :workspace (config origin, hook, validator and spec all identical to the host); warn-mode diagnosis printed and commit created under -P :danger-full-access"
exit 0
