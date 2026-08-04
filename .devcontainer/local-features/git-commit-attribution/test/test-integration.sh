#!/usr/bin/env bash
# End-to-end integration proof for the git-commit-attribution gate: builds the
# real workspace image (devcontainer.json's Feature wiring, Task 8 step 1)
# once, then drives real `git commit` invocations inside it via `docker run`,
# asserting exit codes, stderr, and git log state. This is the proof the
# design's *Testing* table demands (docs/designs/2026-07-10-git-commit-
# attribution-design.md) — unit tests already cover the TypeScript in
# isolation; this suite is the only place the Feature, the mount, the
# dispatcher, and the validator run together as they will in a real container.
#
# `devcontainer up` bind mounts resolve against the outer host, not this
# script's shell — same for a `docker run -v`. This repo's own devcontainer
# runs docker-outside-of-docker: `docker` here talks to the *outer* Docker
# Desktop daemon over a forwarded socket, so a `-v` source is looked up on
# the real host filesystem, and Docker Desktop's file-sharing allowlist only
# recognizes paths already shared into some running container — for us, the
# ancestry of this repo's own bind mount. `resolve_docker_mount_source`
# below translates a path inside this shell into the equivalent path on
# whatever host the docker daemon actually sees, by asking that daemon what
# it thinks this very container's mounts are. Outside a nested-docker
# devcontainer (e.g. a plain CI runner) no translation applies and the path
# is used unchanged.
#
# Spec fixtures are therefore written under a temp directory rooted in this
# worktree (not /tmp — a path only this container can see) so the real host
# daemon can find them; the directory is removed by the EXIT trap regardless
# of outcome, so nothing here is ever staged or committed.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
IMAGE="gca-integration:latest"
TARGET="/etc/devcontainer/feature/git-commit-attribution/trailer-contract"
passed=0
failed=0

pass() { printf 'ok   %s\n' "$1"; passed=$((passed + 1)); }
fail() { printf 'FAIL %s\n     %s\n' "$1" "$2"; failed=$((failed + 1)); }

resolve_docker_mount_source() {
  local target="$1" self mounts best_dest="" best_src=""
  self="$(hostname)"
  mounts="$(docker inspect "$self" --format '{{json .Mounts}}' 2>/dev/null)" || { printf '%s' "$target"; return; }
  while IFS=$'\t' read -r dest src; do
    [ -z "$dest" ] && continue
    case "$target" in
      "$dest" | "$dest"/*)
        if [ "${#dest}" -gt "${#best_dest}" ]; then
          best_dest="$dest"
          best_src="$src"
        fi
        ;;
    esac
  done < <(printf '%s' "$mounts" | jq -r '.[] | select(.Destination != null) | [.Destination, .Source] | @tsv')
  if [ -n "$best_dest" ]; then
    printf '%s' "${target/#$best_dest/$best_src}"
  else
    printf '%s' "$target"
  fi
}

BUILD_LOG="$(mktemp)"
TMP="$(mktemp -d "$REPO_ROOT/.gca-integration-tmp.XXXXXX")"
trap 'rm -rf "$BUILD_LOG" "$TMP"' EXIT

if ! npx -y @devcontainers/cli@latest build \
  --workspace-folder "$REPO_ROOT" --image-name "$IMAGE" >"$BUILD_LOG" 2>&1; then
  cat "$BUILD_LOG"
  echo "FATAL: workspace image build failed" >&2
  exit 1
fi

cat > "$TMP/warn.conf" <<'SPEC'
version      1
mode         warn

trailer      Harness           required
trailer      Harness-Version   required
trailer      Model             required
trailer      Skills            required
trailer      Co-Authored-By    required last

agent-author noreply@anthropic.com
agent-author noreply@openai.com
SPEC
sed 's/^mode         warn/mode         enforce/' "$TMP/warn.conf" > "$TMP/enforce.conf"

WARN_SRC="$(resolve_docker_mount_source "$TMP/warn.conf")"
ENFORCE_SRC="$(resolve_docker_mount_source "$TMP/enforce.conf")"

# Fixtures drawn from the design's *Testing* table / hube/devcontainer#23.
COMPLIANT_MSG='Fix the thing.

Harness: Claude Code
Harness-Version: 2.1.205 (Claude Code)
Model: claude-sonnet-5
Skills: none
Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>'

# hube/devcontainer#23's fabricated block: shape-valid under the pre-mandatory
# grammar, non-compliant now that Skills: is required (design, *Contract
# Change*).
FABRICATED_MSG='Report the finding.

Harness: Claude Code
Harness-Version: 2.1.205 (Claude Code)
Model: claude-haiku-4-5-20251001
Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>'

# worklog-contribute's current hardcoded message (hube/agent-skills#9):
# only Co-Authored-By, model ID where the display name belongs.
WORKLOG_MSG='Contribute worklog entry.

Co-Authored-By: claude-sonnet-5 <noreply@anthropic.com>'

HUMAN_MSG='Fix a typo in the README.'

run_gca() {
  # $1: extra `docker run` args (word-split deliberately; always literal in
  # call sites below). $2: in-container shell script.
  docker run --rm $1 "$IMAGE" bash -lc "$2" 2>&1
}

# ============================================================ 1: enforce + compliant 5-trailer block -> commit created
out1="$(run_gca "-u devcontainer -v $ENFORCE_SRC:$TARGET:ro" '
repo=$(mktemp -d); cd "$repo"; git init --quiet -b main . >/dev/null 2>&1
git -c user.email=t@t -c user.name=t commit --allow-empty -m "'"$COMPLIANT_MSG"'"
echo "COMMIT_RC=$?"
')"; rc1=$?
[ "$rc1" -eq 0 ] && pass "1 enforce+compliant: exit 0" || fail "1 enforce+compliant: exit 0" "got $rc1: $out1"
[[ "$out1" == *"COMMIT_RC=0"* ]] && pass "1 enforce+compliant: commit created" || fail "1 enforce+compliant: commit created" "$out1"

# ============================================================ 2: enforce + fabricated #23 block (no Skills:) -> rejected; stderr names 'Skills'
out2="$(run_gca "-u devcontainer -v $ENFORCE_SRC:$TARGET:ro" '
repo=$(mktemp -d); cd "$repo"; git init --quiet -b main . >/dev/null 2>&1
git -c user.email=t@t -c user.name=t commit --allow-empty -m "'"$FABRICATED_MSG"'"
')"; rc2=$?
[ "$rc2" -ne 0 ] && pass "2 enforce+fabricated: rejected" || fail "2 enforce+fabricated: rejected" "got rc=$rc2: $out2"
[[ "$out2" == *"git-commit-attribution: commit message is missing the required trailer 'Skills'"* ]] \
  && pass "2 enforce+fabricated: stderr names 'Skills'" || fail "2 enforce+fabricated: stderr names 'Skills'" "$out2"
# Discriminating check: the same substring must NOT appear in case 1's
# compliant-message output, or this assertion would pass vacuously against
# any output.
[[ "$out1" != *"'Skills'"* ]] && pass "2 enforce+fabricated: 'Skills' assertion is discriminating (absent from compliant run)" \
  || fail "2 enforce+fabricated: 'Skills' assertion is discriminating (absent from compliant run)" "$out1"

# ============================================================ 3: warn + same fabricated block -> commit created; WARNING printed
out3="$(run_gca "-u devcontainer -v $WARN_SRC:$TARGET:ro" '
repo=$(mktemp -d); cd "$repo"; git init --quiet -b main . >/dev/null 2>&1
git -c user.email=t@t -c user.name=t commit --allow-empty -m "'"$FABRICATED_MSG"'"
echo "COMMIT_RC=$?"
')"; rc3=$?
[ "$rc3" -eq 0 ] && pass "3 warn+fabricated: exit 0" || fail "3 warn+fabricated: exit 0" "got $rc3: $out3"
[[ "$out3" == *"COMMIT_RC=0"* ]] && pass "3 warn+fabricated: commit created" || fail "3 warn+fabricated: commit created" "$out3"
[[ "$out3" == *"git-commit-attribution: WARNING: commit message is missing the required trailer 'Skills'"* ]] \
  && pass "3 warn+fabricated: WARNING printed" || fail "3 warn+fabricated: WARNING printed" "$out3"

# ============================================================ 4: enforce + worklog-contribute's current message -> rejected
out4="$(run_gca "-u devcontainer -v $ENFORCE_SRC:$TARGET:ro" '
repo=$(mktemp -d); cd "$repo"; git init --quiet -b main . >/dev/null 2>&1
git -c user.email=t@t -c user.name=t commit --allow-empty -m "'"$WORKLOG_MSG"'"
')"; rc4=$?
[ "$rc4" -ne 0 ] && pass "4 enforce+worklog-message: rejected" || fail "4 enforce+worklog-message: rejected" "got rc=$rc4: $out4"
[[ "$out4" == *"git-commit-attribution: commit message is missing the required trailer 'Harness'"* ]] \
  && pass "4 enforce+worklog-message: names missing 'Harness'" || fail "4 enforce+worklog-message: names missing 'Harness'" "$out4"

# ============================================================ 5: human commit, no trailers -> created, silently
out5="$(run_gca "-u devcontainer -v $ENFORCE_SRC:$TARGET:ro" '
repo=$(mktemp -d); cd "$repo"; git init --quiet -b main . >/dev/null 2>&1
git -c user.email=t@t -c user.name=t commit --allow-empty -m "'"$HUMAN_MSG"'"
echo "COMMIT_RC=$?"
')"; rc5=$?
[ "$rc5" -eq 0 ] && pass "5 human-no-trailers: exit 0" || fail "5 human-no-trailers: exit 0" "got $rc5: $out5"
[[ "$out5" == *"COMMIT_RC=0"* ]] && pass "5 human-no-trailers: commit created" || fail "5 human-no-trailers: commit created" "$out5"
[[ "$out5" != *"git-commit-attribution"* ]] && pass "5 human-no-trailers: silent (no gate output)" || fail "5 human-no-trailers: silent (no gate output)" "$out5"

# ============================================================ 6: no spec mounted at all -> rejected; names the spec path
out6="$(run_gca "-u devcontainer" '
repo=$(mktemp -d); cd "$repo"; git init --quiet -b main . >/dev/null 2>&1
git -c user.email=t@t -c user.name=t commit --allow-empty -m "'"$HUMAN_MSG"'"
')"; rc6=$?
[ "$rc6" -ne 0 ] && pass "6 no-spec: rejected" || fail "6 no-spec: rejected" "got rc=$rc6: $out6"
[[ "$out6" == *"git-commit-attribution: no spec at $TARGET"* ]] \
  && pass "6 no-spec: names the spec path" || fail "6 no-spec: names the spec path" "$out6"

# ============================================================ 7: spec path mounted as a directory -> rejected; names the spec path
EMPTY_DIR="$TMP/empty-dir"
mkdir -p "$EMPTY_DIR"
EMPTY_DIR_SRC="$(resolve_docker_mount_source "$EMPTY_DIR")"
out7="$(run_gca "-u devcontainer -v $EMPTY_DIR_SRC:$TARGET:ro" '
repo=$(mktemp -d); cd "$repo"; git init --quiet -b main . >/dev/null 2>&1
git -c user.email=t@t -c user.name=t commit --allow-empty -m "'"$HUMAN_MSG"'"
')"; rc7=$?
[ "$rc7" -ne 0 ] && pass "7 spec-is-directory: rejected" || fail "7 spec-is-directory: rejected" "got rc=$rc7: $out7"
[[ "$out7" == *"git-commit-attribution: spec at $TARGET is not a file"* ]] \
  && pass "7 spec-is-directory: names the spec path" || fail "7 spec-is-directory: names the spec path" "$out7"

# ============================================================ 8: git commit --no-verify with a violating msg -> created (documented bypass)
out8="$(run_gca "-u devcontainer -v $ENFORCE_SRC:$TARGET:ro" '
repo=$(mktemp -d); cd "$repo"; git init --quiet -b main . >/dev/null 2>&1
git -c user.email=t@t -c user.name=t commit --no-verify --allow-empty -m "'"$WORKLOG_MSG"'"
echo "COMMIT_RC=$?"
')"; rc8=$?
[ "$rc8" -eq 0 ] && pass "8 no-verify: exit 0" || fail "8 no-verify: exit 0" "got $rc8: $out8"
[[ "$out8" == *"COMMIT_RC=0"* ]] && pass "8 no-verify: commit created" || fail "8 no-verify: commit created" "$out8"
[[ "$out8" != *"git-commit-attribution"* ]] && pass "8 no-verify: gate never ran" || fail "8 no-verify: gate never ran" "$out8"

# ============================================================ 9: commit as root -> gate still applies; rejection names the same /etc path
out9="$(run_gca "-u root -v $ENFORCE_SRC:$TARGET:ro" '
repo=$(mktemp -d); cd "$repo"; git init --quiet -b main . >/dev/null 2>&1
git -c user.email=t@t -c user.name=t commit --allow-empty -m "'"$FABRICATED_MSG"'"
')"; rc9=$?
[ "$rc9" -ne 0 ] && pass "9 root: rejected" || fail "9 root: rejected" "got rc=$rc9: $out9"
[[ "$out9" == *"Spec: $TARGET"* ]] && pass "9 root: rejection names the same /etc path" || fail "9 root: rejection names the same /etc path" "$out9"

# ============================================================ 10: commit from a linked worktree -> gate applies; main .git hooks still chain
out10="$(run_gca "-u devcontainer -v $ENFORCE_SRC:$TARGET:ro" '
set -e
main=$(mktemp -d); cd "$main"; git init --quiet -b main . >/dev/null 2>&1
git -c user.email=t@t -c user.name=t commit --allow-empty -m init >/dev/null
mkdir -p .git/hooks
printf "#!/bin/sh\ntouch \"$main/POST_COMMIT_RAN\"\n" > .git/hooks/post-commit
chmod +x .git/hooks/post-commit
wt=$(mktemp -d)
git worktree add -q "$wt" -b feature >/dev/null
cd "$wt"
git -c user.email=t@t -c user.name=t commit --allow-empty -m "'"$COMPLIANT_MSG"'"
echo "COMMIT_RC=$?"
[ -f "$main/POST_COMMIT_RAN" ] && echo POST_COMMIT_RAN_OK || echo POST_COMMIT_MISSING
')"; rc10=$?
[ "$rc10" -eq 0 ] && pass "10 linked-worktree: exit 0" || fail "10 linked-worktree: exit 0" "got $rc10: $out10"
[[ "$out10" == *"COMMIT_RC=0"* ]] && pass "10 linked-worktree: commit created" || fail "10 linked-worktree: commit created" "$out10"
[[ "$out10" == *"POST_COMMIT_RAN_OK"* ]] && pass "10 linked-worktree: main .git hook chained" || fail "10 linked-worktree: main .git hook chained" "$out10"

# ============================================================ 11: repo with .git/hooks/pre-commit -> still runs with the gate installed
out11="$(run_gca "-u devcontainer -v $ENFORCE_SRC:$TARGET:ro" '
repo=$(mktemp -d); cd "$repo"; git init --quiet -b main . >/dev/null 2>&1
mkdir -p .git/hooks
printf "#!/bin/sh\necho REPO_PRECOMMIT_RAN >&2\nexit 1\n" > .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
git -c user.email=t@t -c user.name=t commit --allow-empty -m "'"$HUMAN_MSG"'"
')"; rc11=$?
[ "$rc11" -ne 0 ] && pass "11 repo-pre-commit: non-zero status propagates" || fail "11 repo-pre-commit: non-zero status propagates" "got rc=$rc11: $out11"
[[ "$out11" == *"REPO_PRECOMMIT_RAN"* ]] && pass "11 repo-pre-commit: repo hook ran" || fail "11 repo-pre-commit: repo hook ran" "$out11"

# ============================================================ 12: GIT_CONFIG_NOSYSTEM=1 + violating msg -> commit created (bypass is real; documented)
out12="$(run_gca "-u devcontainer -e GIT_CONFIG_NOSYSTEM=1 -v $ENFORCE_SRC:$TARGET:ro" '
repo=$(mktemp -d); cd "$repo"; git init --quiet -b main . >/dev/null 2>&1
git -c user.email=t@t -c user.name=t commit --allow-empty -m "'"$WORKLOG_MSG"'"
echo "COMMIT_RC=$?"
')"; rc12=$?
[ "$rc12" -eq 0 ] && pass "12 NOSYSTEM: exit 0" || fail "12 NOSYSTEM: exit 0" "got $rc12: $out12"
[[ "$out12" == *"COMMIT_RC=0"* ]] && pass "12 NOSYSTEM: commit created" || fail "12 NOSYSTEM: commit created" "$out12"
[[ "$out12" != *"git-commit-attribution"* ]] && pass "12 NOSYSTEM: gate never ran" || fail "12 NOSYSTEM: gate never ran" "$out12"

# ============================================================ 13: /usr/local/bin/node symlink -> exists, executable, resolves to nvm current
out13="$(run_gca "" '
test -L /usr/local/bin/node && echo IS_SYMLINK
test -x /usr/local/bin/node && echo IS_EXECUTABLE
resolved=$(readlink -f /usr/local/bin/node)
case "$resolved" in /usr/local/share/nvm/*) echo UNDER_NVM;; esac
current=$(readlink -f /usr/local/share/nvm/current/bin/node)
[ "$resolved" = "$current" ] && echo MATCHES_NVM_CURRENT
')"
[[ "$out13" == *"IS_SYMLINK"* ]] && pass "13 node: is a symlink" || fail "13 node: is a symlink" "$out13"
[[ "$out13" == *"IS_EXECUTABLE"* ]] && pass "13 node: is executable" || fail "13 node: is executable" "$out13"
[[ "$out13" == *"UNDER_NVM"* ]] && pass "13 node: resolves under nvm" || fail "13 node: resolves under nvm" "$out13"
[[ "$out13" == *"MATCHES_NVM_CURRENT"* ]] && pass "13 node: matches nvm current" || fail "13 node: matches nvm current" "$out13"

# ============================================================ 14: /etc/gitconfig core.hooksPath -> equals the gate's hooks dir
out14="$(run_gca "" 'git config --file /etc/gitconfig core.hooksPath')"
[ "$out14" = "/usr/local/share/git-commit-attribution/hooks" ] \
  && pass "14 gitconfig: core.hooksPath equals the gate's hooks dir" \
  || fail "14 gitconfig: core.hooksPath equals the gate's hooks dir" "$out14"

# ============================================================ 15: the mounted contract's bytes equal the $TMP source file (mount carries it unmodified)
docker run --rm -v "$ENFORCE_SRC:$TARGET:ro" "$IMAGE" cat "$TARGET" > "$TMP/mounted-copy.conf"
if cmp -s "$TMP/enforce.conf" "$TMP/mounted-copy.conf"; then
  pass "15 mount-bytes-equal: mounted contract matches the source file exactly"
else
  fail "15 mount-bytes-equal: mounted contract matches the source file exactly" \
    "$(diff "$TMP/enforce.conf" "$TMP/mounted-copy.conf")"
fi

printf '\n%d passed, %d failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
