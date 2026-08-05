#!/usr/bin/env bash
# Probes what the design records under *Verified Behavior* about Codex's inner
# bwrap sandbox: that a command Codex launches there sees the same gate the
# host does — the system git config that routes to it, the hook and validator
# it runs, and the trailer contract they enforce. Every one is compared against
# the host's own value, the three files by the sha256 of their whole contents,
# so "the same gate" means the same bytes and not merely something present at
# the same path. What this does NOT check is that the contract mount is still
# read-only inside the sandbox: no claim in the design rests on that, and under
# `:workspace` the entire root filesystem is mounted read-only in any case.
# This cannot be answered from CI (no bwrap user-namespace support on the
# runner) or from a container where the gate has not been installed, so the
# guards below make this script a safe no-op in both places; it is meant to be
# run manually inside a rebuilt container (tracked in #51).
#
# Visibility is all this probe asserts, and `-P :workspace` — the profile the
# Codex Feature's own postCreateScript.sh launches — is the only profile it
# uses. There is deliberately no end-to-end "commit and check the diagnosis"
# arm, for two reasons that would otherwise invite someone to add one back:
#
#   * Inside a real Codex sandbox a commit is impossible, so there is nothing
#     to assert. `git commit` cannot create `.git/index.lock`: under
#     `:workspace` the repository's `.git` is re-mounted read-only inside an
#     otherwise writable workspace, and under `:read-only` there is no `.git`
#     mount at all because `/` itself is read-only. That is a Codex filesystem
#     policy, upstream of this Feature. A commit arm here would fail with
#     `Unable to create '.../.git/index.lock': Read-only file system`, which
#     says nothing whatever about the gate.
#   * `-P :danger-full-access`, the one built-in profile where `.git` is
#     writable, is not a sandbox: a command run under it reports the host's own
#     mount, user, pid and net namespace ids and a byte-identical
#     /proc/self/mountinfo, whereas `:workspace` and `:read-only` each enter
#     four fresh namespaces. Committing under it would measure the host path,
#     not Codex — and test-integration.sh case 3 already covers that path (warn
#     spec plus a fixture missing `Skills:` gives exit 0, a created commit, and
#     the WARNING on stderr) against a real built image.
#
# This probe never writes or mounts a contract and never flips `mode`. It only
# hashes the live contract at the fixed /etc path, to compare what the sandbox
# sees against what the host sees, so it stays valid whatever that contract
# says — including after the rollout flips `mode` to enforce.
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
# Feature's own postStart script is what reports that. Skipping here keeps a
# consumer misconfiguration from surfacing as a gate failure.
if [[ ! -f "$SPEC" ]]; then
  echo "skip: $SPEC not present (consuming devcontainer.json does not declare the spec mount)"
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

# Every expectation is the host's own value, read here rather than hardcoded,
# so the assertion is "the sandbox sees what the host sees" and nothing in this
# script has to be updated when the validator is rebuilt or the spec changes.
# The digests are whole `sha256sum` lines rather than just the hex, so that a
# failure can relay what the command actually said instead of a fragment of it.
host_hooks_origin="$(git config --show-origin --get core.hooksPath 2>&1 | tr '\t' ' ')"
host_commit_msg_path="$(readlink -f "$HOOKS_DIR/commit-msg" 2>&1)"
host_commit_msg_sha="$(sha256sum "$HOOKS_DIR/commit-msg" 2>&1)"
host_validator_sha="$(sha256sum "$VALIDATOR" 2>&1)"
# The whole contract, not the `mode` line: `version`, `trailer` and
# `agent-author` records decide what the gate accepts just as much as `mode`
# does, so matching one field would not show the sandbox reading the same
# contract.
host_spec_sha="$(sha256sum "$SPEC" 2>&1)"

# A component the host itself cannot read leaves an error string in the
# baseline, and the sandbox would report the same error string — so the
# comparisons below would pass while proving nothing. Reject a baseline that is
# not a real value first. The design's claim is also not merely that
# core.hooksPath has a value, but that it resolves from the system file
# install.sh writes, so the origin is checked and not just the path.
if [[ "$host_hooks_origin" != "file:/etc/gitconfig "* ]]; then
  fail "core.hooksPath does not resolve from /etc/gitconfig on the host, so there is no system-wide gate for this probe to look for inside the sandbox" \
    "git config --show-origin said: $host_hooks_origin"
fi
if [[ ! -e "$host_commit_msg_path" ]]; then
  fail "the host cannot resolve $HOOKS_DIR/commit-msg to an existing file, so the sandbox has no hook to be compared against" \
    "readlink -f said: $host_commit_msg_path"
fi
for baseline in "$host_commit_msg_sha" "$host_validator_sha" "$host_spec_sha"; do
  if [[ ! "$baseline" =~ ^[0-9a-f]{64}\ \ .+$ ]]; then
    fail "the host cannot hash one of the gate's own files, so the sandbox has no bytes to be compared against" \
      "sha256sum said: $baseline"
  fi
done

cat >"$workdir/visibility.sh" <<'VISIBILITY'
# Runs inside the sandbox. Emits one key=value line per component so each can
# be compared against the host's value independently, and so a component that
# is unreadable reports its own error text rather than an empty line. The hook
# is hashed as well as resolved: readlink canonicalises without reading, so a
# path comparison alone would pass on a hook the sandbox cannot actually read.
set -u
hooks_dir=$1
validator=$2
spec=$3
printf 'hooks-origin=%s\n' "$(git config --show-origin --get core.hooksPath 2>&1 | tr '\t' ' ')"
printf 'commit-msg-path=%s\n' "$(readlink -f "$hooks_dir/commit-msg" 2>&1)"
printf 'commit-msg-sha=%s\n' "$(sha256sum "$hooks_dir/commit-msg" 2>&1)"
printf 'validator-sha=%s\n' "$(sha256sum "$validator" 2>&1)"
printf 'spec-sha=%s\n' "$(sha256sum "$spec" 2>&1)"
VISIBILITY

vis_err="$workdir/visibility.err"
# Mirrors the invocation shape postCreateScript.sh uses to launch a command
# inside Codex's inner sandbox: `codex sandbox -P :workspace -C <dir>
# <command>`. The repository above is plain host git and is not itself part of
# what this probes; it exists so the sandboxed command runs where a real commit
# would be attempted.
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
expect_same commit-msg-path "$host_commit_msg_path"
expect_same commit-msg-sha "$host_commit_msg_sha"
expect_same validator-sha "$host_validator_sha"
expect_same spec-sha "$host_spec_sha"

echo "PASS: gate visible inside codex sandbox -P :workspace (config origin, hook bytes, validator bytes and contract bytes all identical to the host)"
exit 0
