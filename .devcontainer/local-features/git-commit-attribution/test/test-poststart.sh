#!/usr/bin/env bash
# Tests postStartScript.sh: warns about a missing/malformed trailer contract
# and about repositories whose local core.hooksPath shadows the gate. Never
# blocks container start, so every case asserts exit 0. All git activity
# happens inside a tmp world; the script's spec path and scan root are
# steered by the GCA_SPEC_PATH / GCA_SCAN_ROOT env seams so this suite never
# touches the ambient filesystem or git config.
set -uo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/devcontainer-feature/git-commit-attribution/postStartScript.sh"
passed=0
failed=0

pass() { printf 'ok   %s\n' "$1"; passed=$((passed + 1)); }
fail() { printf 'FAIL %s\n     %s\n' "$1" "$2"; failed=$((failed + 1)); }

# Builds an isolated world: a scratch SCAN_ROOT and a scratch SPEC path,
# neither overlapping this worktree or the ambient filesystem.
setup_world() {
  WORLD="$(mktemp -d)"
  export GCA_SCAN_ROOT="$WORLD/workspaces"
  mkdir -p "$GCA_SCAN_ROOT"
  export GCA_SPEC_PATH="$WORLD/trailer-contract"
}

teardown_world() { rm -rf "$WORLD"; }

git_c() {
  repo="$1"; shift
  git -C "$repo" -c user.email=t@t -c user.name=t "$@"
}

# ============================================================ 1: spec present, no shadowing repos -> no output, exit 0
setup_world
: > "$GCA_SPEC_PATH"
git init --quiet -b main "$GCA_SCAN_ROOT/repo1" >/dev/null
out="$("$SCRIPT" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && pass "clean: exits 0" || fail "clean: exits 0" "got $rc"
[ -z "$out" ] && pass "clean: no output" || fail "clean: no output" "$out"
teardown_world

# ============================================================ 2: spec missing -> names container path and host-side remedy
setup_world
out="$("$SCRIPT" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && pass "spec missing: exits 0" || fail "spec missing: exits 0" "got $rc"
[[ "$out" == *"$GCA_SPEC_PATH"* ]] && pass "spec missing: names the container path" || fail "spec missing: names the container path" "$out"
[[ "$out" == *"git-commit-attribution.conf"* ]] && pass "spec missing: names the host mount source" || fail "spec missing: names the host mount source" "$out"
[[ "$out" == *"hube/claude-home"* ]] && pass "spec missing: names the claude-home checkout requirement" || fail "spec missing: names the claude-home checkout requirement" "$out"
[[ "$out" == *"Docker created a directory"* ]] && pass "spec missing: names the stray-directory case" || fail "spec missing: names the stray-directory case" "$out"
teardown_world

# ============================================================ 3: spec path is a directory -> same warning shape as missing
setup_world
mkdir -p "$GCA_SPEC_PATH"
out="$("$SCRIPT" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && pass "spec is a directory: exits 0" || fail "spec is a directory: exits 0" "got $rc"
[[ "$out" == *"$GCA_SPEC_PATH"* ]] && pass "spec is a directory: names the container path" || fail "spec is a directory: names the container path" "$out"
[[ "$out" == *"git-commit-attribution.conf"* ]] && pass "spec is a directory: same remedy as missing" || fail "spec is a directory: same remedy as missing" "$out"
teardown_world

# ============================================================ 4: repo under scan root with local core.hooksPath -> named, with its value
setup_world
: > "$GCA_SPEC_PATH"
repo="$GCA_SCAN_ROOT/repo4"
git init --quiet -b main "$repo" >/dev/null
git_c "$repo" config --local core.hooksPath "/some/custom/hooks" >/dev/null
out="$("$SCRIPT" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && pass "shadowing repo: exits 0" || fail "shadowing repo: exits 0" "got $rc"
[[ "$out" == *"$repo"* ]] && pass "shadowing repo: names the repository" || fail "shadowing repo: names the repository" "$out"
[[ "$out" == *"/some/custom/hooks"* ]] && pass "shadowing repo: names the hooksPath value" || fail "shadowing repo: names the hooksPath value" "$out"
teardown_world

# ============================================================ 5: non-repo directories under scan root are skipped silently
setup_world
: > "$GCA_SPEC_PATH"
mkdir -p "$GCA_SCAN_ROOT/not-a-repo"
touch "$GCA_SCAN_ROOT/not-a-repo/some-file"
out="$("$SCRIPT" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && pass "non-repo dir: exits 0" || fail "non-repo dir: exits 0" "got $rc"
[ -z "$out" ] && pass "non-repo dir: skipped silently" || fail "non-repo dir: skipped silently" "$out"
teardown_world

# ============================================================ 6: the script never exits non-zero, even with a hostile scan root
setup_world
rm -rf "$GCA_SCAN_ROOT"
out="$("$SCRIPT" 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && pass "absent scan root: exits 0" || fail "absent scan root: exits 0" "got $rc"
teardown_world

printf '\n%d passed, %d failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
