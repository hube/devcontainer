#!/usr/bin/env bash
# Probes the design's one open question (docs/designs/2026-07-10-git-commit-
# attribution-design.md, *Open Questions*): does a `git commit` launched
# inside Codex's inner bwrap sandbox still see /etc/gitconfig, the hooks
# directory, and the read-only spec mount, so the gate's diagnosis reaches
# stderr? This cannot be answered from CI (no bwrap user-namespace support on
# the runner) or from a container where the gate has not been installed, so
# the guard below makes this script a safe no-op in both places; it is meant
# to be run manually inside the first rebuilt container (tracked in #51).
#
# This probe never writes or mounts its own spec, and never flips `mode`: it
# runs against whatever the live spec at the fixed /etc path already says
# (expected `mode warn` on a not-yet-enforcing container), so the commit
# below is expected to succeed and the WARNING diagnosis on stderr is the
# thing being checked for.
set -uo pipefail

HOOKS_DIR=/usr/local/share/git-commit-attribution/hooks

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

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

git init --quiet -b main "$workdir" >/dev/null
printf '%s' "$MSG" >"$workdir/msg.txt"

err_file="$workdir/stderr.log"
# Mirrors the exact invocation shape postCreateScript.sh uses to launch a
# command inside Codex's inner sandbox: `codex sandbox -P :workspace -C
# <dir> <command>`. Only the commit itself runs inside the sandbox; `git
# init` above is plain host git and not part of what this probes.
out="$(timeout 30s codex sandbox -P :workspace -C "$workdir" \
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
  echo "FAIL: $1" >&2
  printf 'exit=%s\nstdout=%s\nstderr=%s\n' "$rc" "$out" "$err" >&2
  exit 1
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

echo "PASS: gate visible inside Codex sandbox (warn-mode diagnosis printed; commit created)"
exit 0
