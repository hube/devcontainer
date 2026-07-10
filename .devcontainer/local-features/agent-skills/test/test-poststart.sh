#!/usr/bin/env bash
# Tests postStartScript.sh branching. No network and no SSH agent required:
# the "remote" is a local bare repository and `ssh-add` is stubbed on PATH.
set -uo pipefail

HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/devcontainer-feature/agent-skills/postStartScript.sh"
passed=0
failed=0

pass() { printf 'ok   %s\n' "$1"; passed=$((passed + 1)); }
fail() { printf 'FAIL %s\n     %s\n' "$1" "$2"; failed=$((failed + 1)); }

# Builds an isolated world: fake HOME, a bare "remote" whose working tree
# contains a setup.sh that touches a marker, and a stub ssh-add.
# $1 = exit code the stub `ssh-add -l` should return.
setup_world() {
  WORLD="$(mktemp -d)"
  export HOME="$WORLD/home"
  mkdir -p "$HOME"

  local src="$WORLD/src"
  mkdir -p "$src"
  cat > "$src/setup.sh" <<'SETUP'
#!/usr/bin/env bash
touch "$HOME/setup-ran"
SETUP
  git -C "$src" init --quiet -b main
  git -C "$src" -c user.email=t@t -c user.name=t add setup.sh
  git -C "$src" -c user.email=t@t -c user.name=t commit --quiet -m init
  REMOTE="$WORLD/remote.git"
  git clone --quiet --bare "$src" "$REMOTE"

  mkdir -p "$WORLD/stub"
  printf '#!/usr/bin/env bash\nexit %s\n' "$1" > "$WORLD/stub/ssh-add"
  chmod +x "$WORLD/stub/ssh-add"
  export PATH="$WORLD/stub:$PATH"

  CLONE_DIR="$WORLD/clone"
  export AGENT_SKILLS_ENV_FILE="$WORLD/agent-skills.env"
  cat > "$AGENT_SKILLS_ENV_FILE" <<EOF
AGENT_SKILLS_REPO=$REMOTE
AGENT_SKILLS_CLONE_DIR=$CLONE_DIR
EOF
}

teardown_world() { rm -rf "$WORLD"; }

# --- clones when the clone directory is absent, then runs setup.sh
setup_world 0
out="$("$HOOK" 2>&1)"; rc=$?
[[ $rc -eq 0 ]] || fail "clone: exits 0" "got $rc"
[[ -d "$CLONE_DIR/.git" ]] && pass "clone: creates the clone" || fail "clone: creates the clone" "$out"
[[ -f "$HOME/setup-ran" ]] && pass "clone: runs setup.sh" || fail "clone: runs setup.sh" "$out"
teardown_world

# --- fetches an existing clone and never moves the working tree
setup_world 0
git clone --quiet "$REMOTE" "$CLONE_DIR"
git -C "$CLONE_DIR" -c user.email=t@t -c user.name=t commit --quiet --allow-empty -m local
before="$(git -C "$CLONE_DIR" rev-parse HEAD)"
out="$("$HOOK" 2>&1)"; rc=$?
after="$(git -C "$CLONE_DIR" rev-parse HEAD)"
[[ $rc -eq 0 ]] || fail "fetch: exits 0" "got $rc"
[[ "$before" == "$after" ]] && pass "fetch: never moves the working tree" || fail "fetch: never moves the working tree" "$before -> $after"
[[ -f "$HOME/setup-ran" ]] && pass "fetch: still runs setup.sh" || fail "fetch: still runs setup.sh" "$out"
teardown_world

# --- refuses to clone over a non-empty non-git directory
setup_world 0
mkdir -p "$CLONE_DIR"; touch "$CLONE_DIR/precious"
out="$("$HOOK" 2>&1)"; rc=$?
[[ $rc -eq 0 ]] || fail "occupied: exits 0" "got $rc"
[[ -f "$CLONE_DIR/precious" && ! -d "$CLONE_DIR/.git" ]] && pass "occupied: leaves the directory alone" || fail "occupied: leaves the directory alone" "$out"
[[ ! -f "$HOME/setup-ran" ]] && pass "occupied: does not run setup.sh" || fail "occupied: does not run setup.sh" "$out"
[[ "$out" == *"is not a git repository"* ]] && pass "occupied: names the problem" || fail "occupied: names the problem" "$out"
teardown_world

# --- an empty agent is a clear, non-fatal skip
setup_world 1
out="$("$HOOK" 2>&1)"; rc=$?
[[ $rc -eq 0 ]] && pass "no identities: exits 0" || fail "no identities: exits 0" "got $rc"
[[ ! -d "$CLONE_DIR" ]] && pass "no identities: does not clone" || fail "no identities: does not clone" "$out"
[[ "$out" == *"holds no identities"* && "$out" == *"will not load"* && "$out" == *"ssh-add"* ]] \
  && pass "no identities: problem, consequence, remedy" || fail "no identities: problem, consequence, remedy" "$out"
teardown_world

# --- an unreachable agent is reported differently from an empty one
setup_world 2
out="$("$HOOK" 2>&1)"; rc=$?
[[ $rc -eq 0 ]] && pass "unreachable: exits 0" || fail "unreachable: exits 0" "got $rc"
[[ "$out" == *"unreachable"* ]] && pass "unreachable: distinct message" || fail "unreachable: distinct message" "$out"
[[ ! -d "$CLONE_DIR" ]] && pass "unreachable: does not clone" || fail "unreachable: does not clone" "$out"
teardown_world

# --- a dangling skills symlink is called out on the skip path
setup_world 1
mkdir -p "$HOME/.claude/skills"
ln -s "$CLONE_DIR" "$HOME/.claude/skills/hube-agent"
out="$("$HOOK" 2>&1)"; rc=$?
[[ $rc -eq 0 ]] && pass "dangling: exits 0" || fail "dangling: exits 0" "got $rc"
[[ "$out" == *"dangling symlink"* ]] && pass "dangling: warns about the stale symlink" || fail "dangling: warns about the stale symlink" "$out"
teardown_world

# --- an empty, unwritable ~/.claude/skills is a leftover bind-mount point: remove it
# Docker creates a nested bind mount's target inside the parent volume owned by
# root. The bind is gone but the directory persists in the volume, and setup.sh
# cannot symlink into it. chmod 500 reproduces the unwritability without needing
# root here; the hook keys on -w, not on ownership.
setup_world 0
mkdir -p "$HOME/.claude/skills"
chmod 500 "$HOME/.claude/skills"
out="$("$HOOK" 2>&1)"; rc=$?
[[ $rc -eq 0 ]] && pass "stale skills dir: exits 0" || fail "stale skills dir: exits 0" "got $rc"
[[ ! -d "$HOME/.claude/skills" ]] && pass "stale skills dir: removed so setup.sh can recreate it" || fail "stale skills dir: removed so setup.sh can recreate it" "$out"
[[ -f "$HOME/setup-ran" ]] && pass "stale skills dir: setup.sh still runs" || fail "stale skills dir: setup.sh still runs" "$out"
[[ "$out" == *"bind mount"* ]] && pass "stale skills dir: explains where it came from" || fail "stale skills dir: explains where it came from" "$out"
teardown_world

# --- an unwritable skills dir holding other skills is never touched
setup_world 0
mkdir -p "$HOME/.claude/skills/some-other-skill"
chmod 500 "$HOME/.claude/skills"
out="$("$HOOK" 2>&1)"; rc=$?
chmod 700 "$HOME/.claude/skills"
[[ $rc -eq 0 ]] && pass "occupied skills dir: exits 0" || fail "occupied skills dir: exits 0" "got $rc"
[[ -d "$HOME/.claude/skills/some-other-skill" ]] && pass "occupied skills dir: leaves its contents alone" || fail "occupied skills dir: leaves its contents alone" "$out"
[[ ! -f "$HOME/setup-ran" ]] && pass "occupied skills dir: does not run setup.sh" || fail "occupied skills dir: does not run setup.sh" "$out"
[[ "$out" == *"chown"* ]] && pass "occupied skills dir: remedy names chown" || fail "occupied skills dir: remedy names chown" "$out"
teardown_world

# --- a writable skills dir is left exactly as it was
setup_world 0
mkdir -p "$HOME/.claude/skills"
out="$("$HOOK" 2>&1)"; rc=$?
[[ -d "$HOME/.claude/skills" ]] && pass "writable skills dir: untouched" || fail "writable skills dir: untouched" "$out"
[[ "$out" != *"bind mount"* ]] && pass "writable skills dir: no spurious repair warning" || fail "writable skills dir: no spurious repair warning" "$out"
teardown_world

# --- a failed clone surfaces git's own error, not just ours
setup_world 0
sed -i "s|^AGENT_SKILLS_REPO=.*|AGENT_SKILLS_REPO=$WORLD/no-such-remote.git|" "$AGENT_SKILLS_ENV_FILE"
out="$("$HOOK" 2>&1)"; rc=$?
[[ $rc -eq 0 ]] && pass "clone failure: exits 0" || fail "clone failure: exits 0" "got $rc"
# Assert on "git said: fatal:", not bare "fatal:" -- git writes to stderr on its
# own, so a bare match would pass even if the hook relayed nothing.
[[ "$out" == *"git said: fatal:"* ]] && pass "clone failure: relays git's message" || fail "clone failure: relays git's message" "$out"
teardown_world

# --- a failing setup.sh surfaces its own stderr
setup_world 0
out="$("$HOOK" 2>&1)"   # first run clones and installs
printf '#!/usr/bin/env bash\necho "setup exploded" >&2\nexit 1\n' > "$CLONE_DIR/setup.sh"
out="$("$HOOK" 2>&1)"; rc=$?
[[ $rc -eq 0 ]] && pass "setup failure: exits 0" || fail "setup failure: exits 0" "got $rc"
[[ "$out" == *"setup.sh said: setup exploded"* ]] && pass "setup failure: relays setup.sh's message" || fail "setup failure: relays setup.sh's message" "$out"
teardown_world

# --- undefined options name the offending values
setup_world 0
printf 'AGENT_SKILLS_REPO=\nAGENT_SKILLS_CLONE_DIR=\n' > "$AGENT_SKILLS_ENV_FILE"
out="$("$HOOK" 2>&1)"; rc=$?
[[ $rc -eq 0 ]] && pass "undefined options: exits 0" || fail "undefined options: exits 0" "got $rc"
[[ "$out" == *"AGENT_SKILLS_REPO=''"* && "$out" == *"AGENT_SKILLS_CLONE_DIR=''"* ]] \
  && pass "undefined options: echoes both values" || fail "undefined options: echoes both values" "$out"
[[ "$out" == *"Set both in"* ]] && pass "undefined options: remedy is not only rebuild" || fail "undefined options: remedy is not only rebuild" "$out"
teardown_world

# --- a missing environment file is survivable
WORLD="$(mktemp -d)"; export HOME="$WORLD/home"; mkdir -p "$HOME"
export AGENT_SKILLS_ENV_FILE="$WORLD/absent.env"
out="$("$HOOK" 2>&1)"; rc=$?
[[ $rc -eq 0 ]] && pass "no env file: exits 0" || fail "no env file: exits 0" "got $rc"
[[ "$out" == *"$AGENT_SKILLS_ENV_FILE"* && "$out" == *"is missing or unreadable"* ]] \
  && pass "no env file: names the file" || fail "no env file: names the file" "$out"
rm -rf "$WORLD"

# --- install.sh reports every bad option at once, not just the first
INSTALL="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/install.sh"
out="$(REPO='' CLONEDIR='relative/path' _CONTAINER_USER='nosuchuser-xyz' bash "$INSTALL" 2>&1)"; rc=$?
[[ $rc -ne 0 ]] && pass "install: fails on bad options" || fail "install: fails on bad options" "exit $rc"
[[ "$out" == *"'repo' must not be empty"* ]] && pass "install: reports empty repo" || fail "install: reports empty repo" "$out"
[[ "$out" == *"must be an absolute path"* ]] && pass "install: reports relative cloneDir" || fail "install: reports relative cloneDir" "$out"
[[ "$out" == *"nosuchuser-xyz"* ]] && pass "install: reports unknown container user" || fail "install: reports unknown container user" "$out"

# --- an empty cloneDir reports "must not be empty", not a bogus absolute-path error
out="$(REPO='git@example.com:x/y.git' CLONEDIR='' _CONTAINER_USER="$(id -un)" bash "$INSTALL" 2>&1)"; rc=$?
[[ "$out" == *"'cloneDir' must not be empty"* ]] && pass "install: reports empty cloneDir" || fail "install: reports empty cloneDir" "$out"
[[ "$out" != *"must be an absolute path"* ]] && pass "install: no spurious absolute-path error" || fail "install: no spurious absolute-path error" "$out"

printf '\n%d passed, %d failed\n' "$passed" "$failed"
[[ $failed -eq 0 ]]
