# Agent Skills Devcontainer Bootstrap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a local Dev Container Feature that clones the `agent-skills` repository and runs its idempotent `setup.sh` on every container start, so a rebuilt container comes up with `hube-agent` skills loaded.

**Architecture:** A local feature named `agent-skills` declares `repo` and `cloneDir` options and contributes a `postStartCommand`. Its root-phase `install.sh` validates the options, copies a hook script into the container user's home, and persists the resolved option values to an environment file, because the Dev Containers specification exposes feature options to `install.sh` only. The hook script sources that file at start time, clones the repository if absent, fetches if present, and runs `setup.sh`. `dependsOn` guarantees the `ssh` and `workspaces-permissions` features install first, which orders their lifecycle hooks first.

**Tech Stack:** Dev Containers local features, Bash, `@devcontainers/cli` (via `npx`), Docker (via the `docker-outside-of-docker` feature), Ubuntu base image.

Design: [`docs/designs/2026-07-09-agent-skills-devcontainer-bootstrap-design.md`](../designs/2026-07-09-agent-skills-devcontainer-bootstrap-design.md)

Issue: https://github.com/hube/devcontainer/issues/26

## Global Constraints

- Follow the repo's existing local feature pattern under `.devcontainer/local-features/`.
- List local feature entries alphabetically in `.devcontainer/devcontainer.json`. `agent-skills` sorts first.
- Do not hardcode the username as `devcontainer`; use `_CONTAINER_USER`. The container user's home is `/home/${_CONTAINER_USER}`, matching the `ssh` and `claude` features.
- Feature option defaults: `repo` is `git@github.com:hube/agent-skills.git`; `cloneDir` is `/workspaces/agent-skills`.
- Use `dependsOn` for `./local-features/ssh` and `./local-features/workspaces-permissions`. Do not use `overrideFeatureInstallOrder`. A mistyped `installsAfter` id is silently ignored; a mistyped `dependsOn` id fails the build.
- `install.sh` validates every option and reports **all** problems before exiting non-zero.
- `postStartScript.sh` must never fail container start. Every recoverable condition warns to stderr and exits 0.
- Every warning states the problem, then its consequence, then the remedy, in that order.
- The clone is authenticated over SSH only. Never use `GH_TOKEN`; it authenticates as `hube-ai`.
- Never merge into an existing clone. Clone if absent, otherwise `git fetch` only.
- Do not verify or depend on `~/.claude/.gitignore`. `~/.claude` is not a git repository in a devcontainer.
- Keep design docs and `README.md` in sync with implementation behavior.
- Before each commit in this devcontainer, run `ssh-add -l` and verify an identity is available for SSH commit signing.
- Every commit must include `Harness`, `Harness-Version`, `Model`, `Skills` when skills contributed, and `Co-Authored-By` trailers in one contiguous trailer block with no blank line between them. Verify with `git log -1 --pretty=%B | git interpret-trailers --parse`.
- The commit messages below show trailer values as `<harness>`, `<version>`, `<model id>`, and so on. These are not placeholders to leave in place: whoever runs the task substitutes their **own** harness and model. For Claude Code, get the version from `claude --version` and use the model id from the session, with `Co-Authored-By: <model display name> <noreply@anthropic.com>`. A subagent names its own model, not the orchestrator's.

---

## File Structure

- Create `.devcontainer/local-features/agent-skills/devcontainer-feature.json`: feature manifest declaring `repo` and `cloneDir` options, `dependsOn` on the `ssh` and `workspaces-permissions` local features, and the `postStartCommand`.
- Create `.devcontainer/local-features/agent-skills/install.sh`: root-phase installer. Validates options, copies `bin/` into the container user's home, writes the resolved options to `~/.config/devcontainer-feature/agent-skills.env`.
- Create `.devcontainer/local-features/agent-skills/bin/devcontainer-feature/agent-skills/postStartScript.sh`: start-time hook. Sources the environment file, clones or fetches, runs `setup.sh`, and never fails container start.
- Create `.devcontainer/local-features/agent-skills/test/test-poststart.sh`: self-contained Bash test harness for the hook's branching. Uses a local bare git repository as the remote and a stub `ssh-add` on `PATH`, so it needs neither network nor an SSH agent.
- Modify `.devcontainer/devcontainer.json`: add `"./local-features/agent-skills": {}` as the first local feature entry.
- Create `.devcontainer/local-features/agent-skills/README.md`: the feature's own documentation —
  behavior, options, SSH agent requirement, ephemeral-clone caveat. Follows `ccstatusline`'s pattern.
- Modify `README.md`: a one-line pointer to that README. The top-level README carries no per-feature detail.
- Modify `docs/designs/2026-07-09-agent-skills-devcontainer-bootstrap-design.md`: update `Status`.

Task 1 builds the hook and its tests. Task 2 builds the manifest and installer, asserting the baked metadata. Task 3 wires the feature in and asserts install order in a real build. Task 4 updates the docs.

---

### Task 1: The `postStartScript.sh` hook and its tests

**Files:**
- Create: `.devcontainer/local-features/agent-skills/bin/devcontainer-feature/agent-skills/postStartScript.sh`
- Test: `.devcontainer/local-features/agent-skills/test/test-poststart.sh`

**Interfaces:**
- Consumes: an environment file defining `AGENT_SKILLS_REPO` and `AGENT_SKILLS_CLONE_DIR`. Its path defaults to `$HOME/.config/devcontainer-feature/agent-skills.env` and is overridable via `AGENT_SKILLS_ENV_FILE` **for tests only**. Task 2's `install.sh` writes that file.
- Produces: `postStartScript.sh`, invoked with no arguments, always exiting 0.

The `AGENT_SKILLS_ENV_FILE` override exists so the harness can point the hook at a fixture without writing to the real home directory. Production never sets it.

- [ ] **Step 1: Write the failing test**

Create `.devcontainer/local-features/agent-skills/test/test-poststart.sh`:

```bash
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
```

Make it executable:

```bash
chmod +x .devcontainer/local-features/agent-skills/test/test-poststart.sh
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash .devcontainer/local-features/agent-skills/test/test-poststart.sh`

Expected: FAIL. Every assertion fails because the hook does not exist yet; the harness reports `FAIL` lines and a non-zero exit.

- [ ] **Step 3: Write the hook**

Create `.devcontainer/local-features/agent-skills/bin/devcontainer-feature/agent-skills/postStartScript.sh`:

```bash
#!/usr/bin/env bash
# Clones agent-skills if absent, refreshes remote refs if present, then runs the
# repo's own idempotent installer. Never fails container start: an unusable SSH
# agent or an unreachable remote must not stop the container from coming up.
set -uo pipefail

ENV_FILE="${AGENT_SKILLS_ENV_FILE:-$HOME/.config/devcontainer-feature/agent-skills.env}"

warn() { echo "agent-skills: $*" >&2; }

# The ~/.claude volume outlives rebuilds, so the skills symlink can survive a
# clone that did not. Say so rather than deleting what the user owns.
bail() {
  warn "$1"
  local link="$HOME/.claude/skills/hube-agent"
  if [[ -L "$link" && ! -e "$link" ]]; then
    warn "$link is a dangling symlink left by an earlier container, so Claude Code will not load hube-agent skills."
  fi
  exit 0
}

if [[ ! -r "$ENV_FILE" ]]; then
  bail "the options file $ENV_FILE is missing or unreadable, so the bootstrap cannot run. hube-agent skills will not load. Rebuild the container to reinstall the Feature."
fi

source "$ENV_FILE"

repo="${AGENT_SKILLS_REPO:-}"
clone_dir="${AGENT_SKILLS_CLONE_DIR:-}"

if [[ -z "$repo" || -z "$clone_dir" ]]; then
  bail "the options file $ENV_FILE must define both AGENT_SKILLS_REPO and AGENT_SKILLS_CLONE_DIR, but AGENT_SKILLS_REPO='$repo' and AGENT_SKILLS_CLONE_DIR='$clone_dir', so the bootstrap cannot run. hube-agent skills will not load. Set both in $ENV_FILE, or rebuild the container to reinstall the feature."
fi

if [[ -e "$clone_dir" && ! -d "$clone_dir" ]]; then
  bail "$clone_dir exists and is not a directory, so the clone cannot be created. hube-agent skills will not load. Remove it, then restart the container."
fi

if [[ -d "$clone_dir/.git" ]]; then
  if ! output="$(git -C "$clone_dir" fetch --quiet 2>&1)"; then
    warn "git fetch failed in $clone_dir, so its remote refs are stale. Skills still load from the existing clone. git said: ${output:-no output}"
  fi
elif [[ -d "$clone_dir" && -n "$(ls -A "$clone_dir" 2>/dev/null)" ]]; then
  bail "$clone_dir is not empty and is not a git repository, so it will not be cloned over. hube-agent skills will not load. Move it aside, then restart the container."
else
  ssh-add -l >/dev/null 2>&1
  case $? in
    0) ;;
    1) bail "the SSH agent holds no identities, so $repo cannot be cloned. hube-agent skills will not load. Run \`ssh-add\` on the host, then restart the container." ;;
    *) bail "the SSH agent is unreachable at SSH_AUTH_SOCK=${SSH_AUTH_SOCK:-unset}, so $repo cannot be cloned. hube-agent skills will not load. Check SSH agent forwarding on the host, then restart the container." ;;
  esac

  if ! output="$(git clone --quiet "$repo" "$clone_dir" 2>&1)"; then
    bail "cloning $repo into $clone_dir failed, so no skills are installed. hube-agent skills will not load. Check network access and repository permissions, then restart the container. git said: ${output:-no output}"
  fi
fi

if [[ ! -f "$clone_dir/setup.sh" ]]; then
  bail "$clone_dir/setup.sh is missing, so the installer cannot run. hube-agent skills will not load. Check that $repo still ships setup.sh."
fi

# Captured so a failure and its cause arrive as one message. Discards setup.sh's
# success chatter, which nobody reads in container start logs.
if ! output="$(bash "$clone_dir/setup.sh" 2>&1)"; then
  warn "$clone_dir/setup.sh failed, so hube-agent skills may not load. setup.sh said: ${output:-no output}"
fi

exit 0
```

Make it executable:

```bash
chmod +x .devcontainer/local-features/agent-skills/bin/devcontainer-feature/agent-skills/postStartScript.sh
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash .devcontainer/local-features/agent-skills/test/test-poststart.sh`

Expected: PASS. Final line reads `24 passed, 0 failed` and the exit status is 0.

- [ ] **Step 5: Commit**

```bash
ssh-add -l
git add .devcontainer/local-features/agent-skills/bin/devcontainer-feature/agent-skills/postStartScript.sh \
        .devcontainer/local-features/agent-skills/test/test-poststart.sh
git commit -F - <<'EOF'
Add agent-skills bootstrap hook and tests

Clone the repo if absent, fetch if present, never merge, then run its
idempotent setup.sh. The hook always exits 0 so an unusable SSH agent
cannot stop the container from starting; each warning names the problem,
its consequence, and the remedy.

Harness: <harness>
Harness-Version: <version>
Model: <model id>
Skills: <skills>
Co-Authored-By: <model display name> <noreply address>
EOF
git log -1 --pretty=%B | git interpret-trailers --parse
```

---

### Task 2: The feature manifest and installer

**Files:**
- Create: `.devcontainer/local-features/agent-skills/devcontainer-feature.json`
- Create: `.devcontainer/local-features/agent-skills/install.sh`

**Interfaces:**
- Consumes: `postStartScript.sh` from Task 1, at `bin/devcontainer-feature/agent-skills/postStartScript.sh` relative to the feature directory.
- Produces: `~/.config/devcontainer-feature/agent-skills.env`, defining `AGENT_SKILLS_REPO` and `AGENT_SKILLS_CLONE_DIR`. The feature contributes `postStartCommand` = `~/bin/devcontainer-feature/agent-skills/postStartScript.sh`.

The Dev Containers specification emits feature options to `install.sh` as uppercased environment variables (`repo` → `REPO`, `cloneDir` → `CLONEDIR`) and to nothing else, which is why the installer persists them to a file.

- [ ] **Step 1: Write the failing test**

`install.sh` validation is the testable unit; it runs before any side effect, so it can be exercised without root. Append this block to `.devcontainer/local-features/agent-skills/test/test-poststart.sh`, immediately **before** the final `printf '\n%d passed, %d failed\n'` line:

```bash
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
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash .devcontainer/local-features/agent-skills/test/test-poststart.sh`

Expected: FAIL. The six new assertions fail with `bash: .../install.sh: No such file or directory`; the twenty-four from Task 1 still pass.

- [ ] **Step 3: Write the manifest and the installer**

Create `.devcontainer/local-features/agent-skills/devcontainer-feature.json`:

```json
{
  "id": "agent-skills",
  "name": "Agent skills",
  "version": "1.0.0",
  "dependsOn": {
    "./local-features/ssh": {},
    "./local-features/workspaces-permissions": {}
  },
  "installsAfter": ["ghcr.io/devcontainers/features/common-utils"],
  "options": {
    "repo": {
      "type": "string",
      "description": "Git remote to clone",
      "default": "git@github.com:hube/agent-skills.git"
    },
    "cloneDir": {
      "type": "string",
      "description": "Absolute path the repo is cloned to",
      "default": "/workspaces/agent-skills"
    }
  },
  "postStartCommand": "~/bin/devcontainer-feature/agent-skills/postStartScript.sh"
}
```

`dependsOn` paths resolve relative to the directory holding `devcontainer.json`, which is why they read `./local-features/...` and not `../ssh`.

Create `.devcontainer/local-features/agent-skills/install.sh`:

```bash
#!/usr/bin/env bash
# feature options reach install.sh and nothing else, so persist them for the
# postStart hook to source.
set -euo pipefail

errors=()

[[ -n "${REPO:-}" ]] || errors+=("option 'repo' must not be empty")

if [[ -z "${CLONEDIR:-}" ]]; then
  errors+=("option 'cloneDir' must not be empty")
elif [[ "${CLONEDIR}" != /* ]]; then
  errors+=("option 'cloneDir' must be an absolute path, got '${CLONEDIR}'")
fi

if [[ -z "${_CONTAINER_USER:-}" ]] || ! id "${_CONTAINER_USER}" >/dev/null 2>&1; then
  errors+=("container user '${_CONTAINER_USER:-}' does not exist")
fi

if (( ${#errors[@]} > 0 )); then
  printf 'agent-skills: %s\n' "${errors[@]}" >&2
  exit 1
fi

echo ">Installing agent-skills bootstrap"

user_home="/home/${_CONTAINER_USER}"

rsync -rp \
    --chown="${_CONTAINER_USER}:${_CONTAINER_USER}" \
    --chmod=D755,F755 \
    bin "${user_home}"

env_dir="${user_home}/.config/devcontainer-feature"
install -d -o "${_CONTAINER_USER}" -g "${_CONTAINER_USER}" -m 0755 "${env_dir}"

env_file="${env_dir}/agent-skills.env"
{
  printf 'AGENT_SKILLS_REPO=%q\n' "${REPO}"
  printf 'AGENT_SKILLS_CLONE_DIR=%q\n' "${CLONEDIR}"
} > "${env_file}"
chown "${_CONTAINER_USER}:${_CONTAINER_USER}" "${env_file}"
chmod 0644 "${env_file}"

echo ">Done installing agent-skills bootstrap"
```

`printf %q` quotes the values so a path containing spaces survives being sourced.

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash .devcontainer/local-features/agent-skills/test/test-poststart.sh`

Expected: PASS. Final line reads `30 passed, 0 failed`.

- [ ] **Step 5: Verify the feature builds and bakes the hook into image metadata**

The `docker-outside-of-docker` feature supplies a working daemon, so this runs from inside the devcontainer.

```bash
npx -y @devcontainers/cli@latest build \
  --workspace-folder . --image-name dc-verify:latest --no-cache 2>&1 | tail -3
docker inspect dc-verify:latest \
  --format '{{ index .Config.Labels "devcontainer.metadata" }}' \
  | python3 -c 'import json,sys; [print(e.get("id"), "|", e.get("postStartCommand")) for e in json.load(sys.stdin) if e.get("id")]'
```

Expected: the build reports `{"outcome":"success",...}`. The metadata does **not** yet list `./local-features/agent-skills`, because Task 3 has not wired it into `devcontainer.json`. This step establishes the baseline the next task changes.

- [ ] **Step 6: Commit**

```bash
ssh-add -l
git add .devcontainer/local-features/agent-skills/devcontainer-feature.json \
        .devcontainer/local-features/agent-skills/install.sh \
        .devcontainer/local-features/agent-skills/test/test-poststart.sh
git commit -F - <<'EOF'
Add agent-skills feature manifest and installer

Options reach install.sh and nothing else, so the installer persists the
resolved repo and cloneDir to an env file the postStart hook sources.
Validate every option and report all problems at once. Depend on the ssh
and workspaces-permissions features so their hooks run first.

Harness: <harness>
Harness-Version: <version>
Model: <model id>
Skills: <skills>
Co-Authored-By: <model display name> <noreply address>
EOF
git log -1 --pretty=%B | git interpret-trailers --parse
```

---

### Task 3: Wire the feature into `devcontainer.json`

**Files:**
- Modify: `.devcontainer/devcontainer.json`

**Interfaces:**
- Consumes: the `agent-skills` feature from Task 2.
- Produces: an image whose `devcontainer.metadata` label lists `./local-features/ssh` and `./local-features/workspaces-permissions` before `./local-features/agent-skills`.

- [ ] **Step 1: Add the feature entry**

In `.devcontainer/devcontainer.json`, add `"./local-features/agent-skills": {}` as the first local feature, keeping the list alphabetical. The `features` object becomes:

```json
  "features": {
    "ghcr.io/devcontainers/features/common-utils:2": {
      "configureZshAsDefaultShell": true,
      "username": "${localEnv:USERNAME:devcontainer}"
    },
    "ghcr.io/devcontainers/features/docker-outside-of-docker:1": {
      "moby": false
    },
    "ghcr.io/devcontainers/features/github-cli:1": {},
    "./local-features/agent-skills": {},
    "./local-features/ccstatusline": {},
    "./local-features/claude": {},
    "./local-features/codex": {},
    "./local-features/direnv": {},
    "./local-features/ssh": {},
    "./local-features/workspaces-permissions": {}
  },
```

- [ ] **Step 2: Write the failing ordering assertion**

Create `.devcontainer/local-features/agent-skills/test/test-install-order.sh`:

```bash
#!/usr/bin/env bash
# Asserts that dependsOn puts ssh and workspaces-permissions ahead of
# agent-skills, so their postStart hooks run first. A mistyped installsAfter id
# is silently ignored by the CLI, so this must be asserted, never assumed.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
IMAGE="dc-order-assert:latest"
BUILD_LOG="$(mktemp)"
trap 'rm -f "$BUILD_LOG"' EXIT

if ! npx -y @devcontainers/cli@latest build \
  --workspace-folder "$REPO_ROOT" --image-name "$IMAGE" >"$BUILD_LOG" 2>&1; then
  cat "$BUILD_LOG"
  exit 1
fi

docker inspect "$IMAGE" --format '{{ index .Config.Labels "devcontainer.metadata" }}' \
  | python3 -c '
import json, sys

def check(cond, msg):
    # Bare assert is stripped under PYTHONOPTIMIZE/-O, which would make this
    # script print success unconditionally on a real ordering regression.
    if not cond:
        raise SystemExit(msg)

meta = json.load(sys.stdin)
ids = [e["id"] for e in meta if e.get("id")]
check("./local-features/agent-skills" in ids,
      f"./local-features/agent-skills missing from metadata: {ids}")
for dep in ("./local-features/ssh", "./local-features/workspaces-permissions"):
    check(dep in ids, f"{dep} missing from metadata: {ids}")
    check(ids.index(dep) < ids.index("./local-features/agent-skills"),
          f"{dep} must install before ./local-features/agent-skills, got {ids}")
hooks = [e for e in meta if e.get("id") == "./local-features/agent-skills"]
check(len(hooks) == 1, f"expected exactly one agent-skills metadata entry, got {len(hooks)}")
hook = hooks[0]
expected = "~/bin/devcontainer-feature/agent-skills/postStartScript.sh"
actual = hook.get("postStartCommand")
check(actual == expected, f"bad hook: {actual}")
print("install order and postStartCommand verified")
'
```

Make it executable:

```bash
chmod +x .devcontainer/local-features/agent-skills/test/test-install-order.sh
```

- [ ] **Step 3: Run the assertion**

Run: `bash .devcontainer/local-features/agent-skills/test/test-install-order.sh`

Expected: PASS, printing `install order and postStartCommand verified`. The build takes a few minutes.

If it fails with an `AssertionError` on ordering, `dependsOn` did not resolve. Do not paper over it with `overrideFeatureInstallOrder`; instead move the hook to `postAttachCommand`, whose phase ordering the specification guarantees, and record the change in the design doc.

- [ ] **Step 4: Clean up the verification image**

```bash
docker rmi -f dc-order-assert:latest dc-verify:latest >/dev/null 2>&1 || true
```

- [ ] **Step 5: Commit**

```bash
ssh-add -l
git add .devcontainer/devcontainer.json \
        .devcontainer/local-features/agent-skills/test/test-install-order.sh
git commit -F - <<'EOF'
Enable the agent-skills bootstrap feature

Wire the feature into devcontainer.json and assert from the built image's
metadata label that ssh and workspaces-permissions install ahead of it, so
their postStart hooks run first. A mistyped installsAfter id is silently
ignored, so the order is asserted rather than assumed.

Harness: <harness>
Harness-Version: <version>
Model: <model id>
Skills: <skills>
Co-Authored-By: <model display name> <noreply address>
EOF
git log -1 --pretty=%B | git interpret-trailers --parse
```

---

### Task 4: Documentation

**Files:**
- Modify: `README.md`
- Modify: `docs/designs/2026-07-09-agent-skills-devcontainer-bootstrap-design.md:3`

**Interfaces:**
- Consumes: the behavior implemented in Tasks 1 through 3.
- Produces: no code.

- [ ] **Step 1: Document the bootstrap in `README.md`**

In `README.md`, extend the bulleted list of what the devcontainer includes so it ends with a new entry:

```markdown
* Claude Code, with the `hube-agent` skills cloned and installed on container start
```

Then add this section immediately after the paragraph beginning "Configurations that mount a volume over `/workspaces` itself":

```markdown
On container start, the `agent-skills` feature clones
`git@github.com:hube/agent-skills.git` into `/workspaces/agent-skills` if it is
absent, refreshes its remote refs if it is present, and runs the repository's
own idempotent `setup.sh`. Cloning uses the forwarded SSH agent. If the agent
holds no identities the container still starts, and the feature explains on
stderr that skills will not load until you run `ssh-add` on the host and
restart.

The clone is scratch space. `/workspaces/<project>` is a bind mount of the host
directory you opened, but sibling directories such as `/workspaces/agent-skills`
live on the container filesystem and are destroyed on rebuild. Edit
`agent-skills` from its own workspace, where the repository is bind-mounted from
the host.

Both the remote and the clone path are feature options, `repo` and `cloneDir`.
```

- [ ] **Step 2: Update the design document status**

In `docs/designs/2026-07-09-agent-skills-devcontainer-bootstrap-design.md`, change line 3 from:

```markdown
Status: Planned
```

to:

```markdown
Status: Implemented
```

- [ ] **Step 3: Verify the docs match the implementation**

Run:

```bash
grep -n "agent-skills" README.md
grep -n "^Status:" docs/designs/2026-07-09-agent-skills-devcontainer-bootstrap-design.md
grep -c "overrideFeatureInstallOrder" README.md || true
```

Expected: `README.md` mentions the bootstrap, the design doc reads `Status: Implemented`, and `README.md` never mentions `overrideFeatureInstallOrder`.

- [ ] **Step 4: Commit**

```bash
ssh-add -l
git add README.md docs/designs/2026-07-09-agent-skills-devcontainer-bootstrap-design.md
git commit -F - <<'EOF'
Document the agent-skills bootstrap

Describe the clone-and-setup behavior, the SSH agent requirement, and the
fact that sibling directories under /workspaces are scratch space that a
rebuild destroys. Mark the design implemented.

Harness: <harness>
Harness-Version: <version>
Model: <model id>
Skills: <skills>
Co-Authored-By: <model display name> <noreply address>
EOF
git log -1 --pretty=%B | git interpret-trailers --parse
```

---

## Out of Scope

- Codex's `~/.agents/skills`. Tracked in hube/agent-skills#26 and its sub-issue #24.
- Removing the redundant `~/.claude/.gitignore` step from `setup.sh`. Tracked in hube/agent-skills#37.
- Updating the `agent-skills` README to describe the automatic bootstrap. That repository is private and separate; the design's Codebase Impact section lists it, and it should be done there once this lands. It is not a task here because nothing in this repository depends on it.
- Deciding which `/workspaces` subdirectories survive a rebuild. Tracked in #30.
- Persisting the clone across rebuilds with a named volume. Rejected in the design: it would shadow the bind mount when `agent-skills` is itself the workspace.

## Final Verification

These require a host, because `docker-outside-of-docker` resolves bind sources on the host and `devcontainer up` therefore cannot run in-container. After rebuilding from the host:

```bash
test -d /workspaces/agent-skills/.git
readlink ~/.claude/skills/hube-agent                    # /workspaces/agent-skills
readlink ~/bin/ccstatusline-worklog-cache-session-cost  # /workspaces/agent-skills/bin/...
```

Then confirm the behaviors those commands do not cover:

- Re-running `~/bin/devcontainer-feature/agent-skills/postStartScript.sh` is a no-op.
- The start logs show the `ssh` hook before the `agent-skills` hook.
- `ssh-add -D` on the host, then a fresh `devcontainer up`, leaves a running container whose logs name the problem, the consequence, and the remedy.
- A consumer repository whose `devcontainer.json` is only `{"image": "ghcr.io/hube/devcontainer:latest"}` bootstraps with no change of its own, once the image is republished.
