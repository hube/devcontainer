# Codex Image-Consumer Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Status:** Complete.

**Goal:** Make successful fixture rediscovery preserve a zero cleanup status while retaining real discovery and removal failures.

**Architecture:** Keep the image-consumer harness's existing arrays, Docker queries, matching rules, and exit trap. Add explicit successful returns to the two discovery functions and exercise the real script through stubbed Docker and Dev Container CLI boundaries so duplicate rediscovery is proven without a Docker engine.

**Tech Stack:** Bash 5, Python 3 for deterministic fixture-ID generation, Git.

**Design:** [`docs/designs/2026-07-16-codex-image-consumer-cleanup-design.md`](../designs/2026-07-16-codex-image-consumer-cleanup-design.md)

## Global Constraints

- Successful Docker enumeration and deduplication return zero explicitly, including when every matching resource was already known.
- Preserve the existing nonzero return and ordered diagnostic when the underlying Docker enumeration command fails.
- Do not change fixture ownership, matching rules, removal order, or cleanup diagnostics.
- The regression test must exercise the real `test-image-consumer.sh`; it must not copy the discovery functions into the test.
- Follow test-driven development: capture the expected duplicate-rediscovery failure before changing production code, then capture the passing result after the minimal fix.

---

### Task 1: Preserve duplicate-rediscovery success

**Files:**

- Create: `.devcontainer/local-features/codex/test/test-image-consumer-cleanup.sh`
- Modify: `.devcontainer/local-features/codex/test/test-image-consumer.sh`
- Modify: `docs/implementation-plans/2026-07-16-codex-image-consumer-cleanup-implementation-plan.md`

**Interfaces:**

- Consumes: `test-image-consumer.sh IMAGE`, including its exact-label container discovery, deterministic volume suffix, exit trap, and Docker-path wrapper.
- Produces: a non-Docker regression command, `bash .devcontainer/local-features/codex/test/test-image-consumer-cleanup.sh`, plus explicit zero-status contracts for `discover_fixture_containers` and `discover_fixture_volumes`.

- [x] **Step 1: Write the failing whole-wrapper regression test**

Create `test-image-consumer-cleanup.sh`. It must:

1. create an isolated temporary HOME, stub directory, state directory, and log;
2. stub `docker inspect` with bind mounts mapping the repository and `$HOME/.ssh` to themselves;
3. make `docker info` report `Docker Desktop`;
4. make every exact-label `docker ps` call return `fixture-container` and derive the volume suffix from the label token with the same SHA-256/base32 algorithm as the production script;
5. make `docker volume ls` return `fixture-volume-<derived suffix>`;
6. log successful container and volume removals;
7. stub `npx ... up` with `{"containerId":"fixture-container"}` and stub `npx ... exec` as either success or status 23 with `stub exec failed` on stderr;
8. run the real consumer script twice against `fixture-image:test`:
   - success world: require status 0, the production success line, and one removal of each fixture;
   - failing-exec world: require status 23, the existing ordered `devcontainer exec` diagnostic, and one removal of each fixture.

Use this complete test implementation:

```bash
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
```

The Docker stub must derive the suffix from the exact label rather than accepting every volume name. This preserves the production ownership boundary in the regression.

- [x] **Step 2: Run the focused test and verify RED**

Run:

```bash
bash .devcontainer/local-features/codex/test/test-image-consumer-cleanup.sh
```

Expected: nonzero. The success world prints the real consumer success line but the test reports `duplicate rediscovery changed successful status to 1`. This is the intended failure: the wrapped operation succeeds and only the exit trap changes its status.

- [x] **Step 3: Implement the minimal successful-return contract**

In each production discovery function, add an explicit zero return after the existing `while ... done` loop:

```bash
  done <<<"$output"
  return 0
}
```

Do not change the loop body or the existing Docker-command failure block.

- [x] **Step 4: Run the focused test and verify GREEN**

Run:

```bash
bash .devcontainer/local-features/codex/test/test-image-consumer-cleanup.sh
```

Expected output ends with:

```text
PASS: duplicate fixture rediscovery preserves successful cleanup status
PASS: successful cleanup preserves the original nonzero status
```

Expected status: zero.

- [x] **Step 5: Run complete verification**

Run:

```bash
set -e
bash .devcontainer/local-features/codex/test/test-image-consumer-cleanup.sh
bash .devcontainer/local-features/codex/test/test-postcreate.sh
bash .devcontainer/local-features/codex/test/test-runtime-cleanup.sh
bash .devcontainer/local-features/codex/test/test-documentation.sh
python3 .devcontainer/local-features/codex/test/test-feature-config.py
bash .devcontainer/local-features/agent-skills/test/test-poststart.sh
bash .devcontainer/local-features/github-cli-config/test/test-poststart.sh
bash .devcontainer/local-features/github-cli-config/test/test-documentation.sh
python3 .devcontainer/local-features/github-cli-config/test/test-feature-config.py
bash -n .devcontainer/local-features/codex/test/test-image-consumer.sh \
  .devcontainer/local-features/codex/test/test-image-consumer-cleanup.sh
git diff --check
```

Then, against Docker Desktop and the explicitly pulled post-merge image, run:

```bash
bash .devcontainer/local-features/codex/test/test-image-consumer.sh ghcr.io/hube/devcontainer:latest
```

Expected: zero and `Image 'ghcr.io/hube/devcontainer:latest': post-create health and sandboxed patch persistence were verified.` This verifies the local harness change against the published image; the image itself is unchanged.

- [x] **Step 6: Complete the execution record and commit**

Change this plan's status to `Complete.` and mark all Task 1 checkboxes complete only after the commands in Steps 4 and 5 exit zero. Before committing, run `git status --short`, `git diff`, `git diff --check`, `ssh-add -l`, and `codex --version`. Stage only the three task files and commit with the current Codex metadata, the skills actually used, and the required OpenAI co-author trailer.
