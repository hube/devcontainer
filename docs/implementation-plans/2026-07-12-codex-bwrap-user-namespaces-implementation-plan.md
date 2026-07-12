# Codex Bubblewrap User Namespaces Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let Codex's Bubblewrap-based patch helper apply edits in this devcontainer by shipping a custom seccomp profile that permits unprivileged user namespaces, scoped entirely to the Codex local feature.

**Architecture:** The Codex feature vendors a pinned copy of Moby's default seccomp profile with three targeted edits, activates it through its own `securityOpt` (no top-level `devcontainer.json` change), installs `bubblewrap` so a system `bwrap` exists, and runs a `postCreateCommand` smoke test that fails the container create if the capability is missing.

**Tech Stack:** Dev Container Features (JSON metadata + `install.sh`), Bash, `jq`, Docker, `@devcontainers/cli` (via `npx`), Moby seccomp profiles.

**Spec:** `docs/designs/2026-07-11-codex-bwrap-user-namespaces-design.md` (approved, merged in PR #39). Resolves [issue #36](https://github.com/hube/devcontainer/issues/36).

## Global Constraints

- **All new files live under `.devcontainer/local-features/codex/`.** The top-level `.devcontainer/devcontainer.json` must not be modified by any task.
- **Upstream profile source:** `https://raw.githubusercontent.com/moby/profiles/seccomp/v0.2.3/seccomp/default.json`
- **Upstream profile SHA-256:** `536529b665dd0972c37bfb569f5d4ac8a53592e7b00752bc39ff063ca9864c74`
- **Scope is Docker Desktop hosts only.** No AppArmor handling.
- **Error messages state problem, then consequence, then remedy, in that order, and include the failing command's own output.** This is the house style; see `local-features/agent-skills/bin/devcontainer-feature/agent-skills/postStartScript.sh`.
- **Tests are Bash scripts in the feature's `test/` directory**, named `test-*.sh`, using the `pass`/`fail` counter harness from `local-features/agent-skills/test/test-poststart.sh`, exiting non-zero if any assertion failed.
- **Behavioral Docker tests are hermetic.** Every build uses a unique temporary image tag, exits immediately with Docker's output if the build fails, and removes the image from an `EXIT` trap.
- **The final test-suite command runs every test and exits non-zero if any test failed.** Reporting a failure must never consume its status and turn the verification gate green.
- **Before every commit:** rerun the task's exact verification, run `ssh-add -l`, inspect `git status` and `git diff`, stop on any failure, then stage only the task's listed files.
- **Every commit needs the metadata trailer block and a `Co-Authored-By` trailer** as one contiguous paragraph with no blank line between them, per `CLAUDE.md`. Verify with `git log -1 --pretty=%B | git interpret-trailers --parse` before moving on.
- **Commit metadata must describe the actual executor.** Populate `Skills:` with the skills that contributed to that commit, and omit the line when none contributed; do not copy a fixed skill name from this plan.

## Background the implementer needs

Docker's default seccomp profile has `"defaultAction": "SCMP_ACT_ERRNO"` — a syscall is denied unless some rule allows it. In `seccomp/v0.2.3` the relevant rules are:

- A rule allowing `clone`, `clone3`, `mount`, `setns`, `umount2`, `unshare` **only when the container has `CAP_SYS_ADMIN`** (`"includes": {"caps": ["CAP_SYS_ADMIN"]}`). This container does not have that capability, so Docker never emits this rule into the filter.
- A rule allowing `clone` **only when no namespace flags are set**: `"args": [{"index": 0, "value": 2114060288, "op": "SCMP_CMP_MASKED_EQ"}]`. That value is `0x7e020000`, exactly the `CLONE_NEW*` bits. This is what denies `CLONE_NEWUSER`.
- A rule returning `ENOSYS` (`errnoRet: 38`) for `clone3` without `CAP_SYS_ADMIN`. **Leave this alone.** Seccomp cannot inspect `clone3`'s flags (they sit behind a userspace pointer), so upstream forces glibc to fall back to `clone`, where the flag filter *can* be enforced. Ungating `clone3` would open an unfilterable namespace path.
- `pivot_root` appears **nowhere** in the profile, so it is denied by the default action rather than capability-gated. Allowing it is a genuine widening, not an ungating.

The mount-family syscalls are required, not optional: Docker compiles the filter from the container's bounding capabilities at start time, so the `CAP_SYS_ADMIN` that Bubblewrap gains *inside* its new user namespace is invisible to the filter. Allowing only `unshare`/`clone` would let bwrap create the namespace and then die at `mount`/`pivot_root`.

**The fix is already validated.** Under the stock profile, `bwrap --unshare-all --dev-bind / / true` reproduces issue #36's exact error (`bwrap: No permissions to create a new namespace...`); under the profile this plan generates, it exits 0.

## File Structure

| File | Responsibility |
|---|---|
| `.devcontainer/local-features/codex/seccomp/userns.json` (create) | The vendored, edited seccomp profile Docker loads. |
| `.devcontainer/local-features/codex/seccomp/README.md` (create) | Provenance: upstream tag, checksum, exact edits, re-vendoring procedure. JSON cannot carry comments, so this file is the record. |
| `.devcontainer/local-features/codex/test/test-seccomp-profile.sh` (create) | Proves the profile has the intended shape *and* actually enables bwrap at runtime. |
| `.devcontainer/local-features/codex/devcontainer-feature.json` (modify) | Adds `securityOpt` (activates the profile) and `postCreateCommand` (runs the smoke test). |
| `.devcontainer/local-features/codex/test/test-metadata.sh` (create) | Proves the feature's `securityOpt`/`postCreateCommand` reach the built image's `devcontainer.metadata` label. |
| `.devcontainer/local-features/codex/bin/devcontainer-feature/codex/postCreateScript.sh` (create) | The create-time smoke test that fails the build if user namespaces are unavailable. |
| `.devcontainer/local-features/codex/install.sh` (modify) | Installs `bubblewrap` explicitly and copies `bin/` into the user's home. |
| `.devcontainer/local-features/codex/test/test-postcreate.sh` (create) | Unit-tests the smoke test's success and failure paths without a container rebuild. |
| `.devcontainer/local-features/codex/NOTES.md` (create) | How to configure the feature correctly. |
| `README.md` (modify) | Points at the new NOTES.md, matching how `agent-skills` is referenced. |
| `docs/designs/2026-07-11-codex-bwrap-user-namespaces-design.md` (modify) | Status update + correct the stale claim that `bwrap` ships in the image. |

---

### Task 1: Vendor the seccomp profile with provenance

**Files:**
- Create: `.devcontainer/local-features/codex/seccomp/userns.json`
- Create: `.devcontainer/local-features/codex/seccomp/README.md`
- Test: `.devcontainer/local-features/codex/test/test-seccomp-profile.sh`

**Interfaces:**
- Consumes: nothing.
- Produces: the profile at path `.devcontainer/local-features/codex/seccomp/userns.json`. Task 2 references this exact path in `securityOpt`; do not rename it.

- [ ] **Step 1: Write the failing test**

Create `.devcontainer/local-features/codex/test/test-seccomp-profile.sh`:

```bash
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

  # Control: the stock profile must still fail, and fail for the reason #36 reports.
  out="$(docker run --rm "$IMAGE" bwrap --unshare-all --dev-bind / / true 2>&1)"; rc=$?
  if [[ $rc -ne 0 && "$out" == *"No permissions to create a new namespace"* ]]; then
    pass "control: stock profile reproduces issue #36"
  elif [[ $rc -eq 0 ]]; then
    fail "control: stock profile reproduces issue #36" \
      "Bubblewrap unexpectedly succeeded under Docker's stock seccomp profile." \
      "the control no longer proves that the treatment result comes from userns.json." \
      "verify the Docker daemon's default seccomp policy, then rerun this test." \
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
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
chmod +x .devcontainer/local-features/codex/test/test-seccomp-profile.sh
.devcontainer/local-features/codex/test/test-seccomp-profile.sh
```

Expected: exits non-zero with wrapper-owned `Problem:`, `Consequence:`, and `Remedy:` lines, followed by `Profile check said:` and the actual missing-file diagnostic.

- [ ] **Step 3: Generate the profile**

Run exactly this. Do not hand-edit the JSON — the transformation must be reproducible from the pinned upstream file, which is the whole point of the provenance record.

```bash
mkdir -p .devcontainer/local-features/codex/seccomp
curl -fsSL -o /tmp/moby-seccomp-default.json \
  https://raw.githubusercontent.com/moby/profiles/seccomp/v0.2.3/seccomp/default.json
echo "536529b665dd0972c37bfb569f5d4ac8a53592e7b00752bc39ff063ca9864c74  /tmp/moby-seccomp-default.json" \
  | sha256sum -c -
jq '
  .syscalls |= (
    map(if (.names | index("clone")) and has("args") then del(.args) else . end)
    + [{"names":["mount","umount2","setns","unshare","pivot_root"],"action":"SCMP_ACT_ALLOW"}]
  )
' /tmp/moby-seccomp-default.json > .devcontainer/local-features/codex/seccomp/userns.json
```

Expected: `sha256sum -c` prints `/tmp/moby-seccomp-default.json: OK`. If it does not, **stop** — upstream retagged or the download is corrupt, and the checksum in the README would be a lie.

- [ ] **Step 4: Run the test to verify it passes**

```bash
.devcontainer/local-features/codex/test/test-seccomp-profile.sh
```

Expected: all assertions `ok`, ending `12 passed, 0 failed`. If Docker is unavailable, the test ends `9 passed, 0 failed` after a warning that states the problem, consequence, and remedy and includes the actual `docker info` output under `docker info said:`. The control assertion proves the stock profile still breaks bwrap; the treatment assertion proves ours fixes it.

- [ ] **Step 5: Write the provenance README**

Create `.devcontainer/local-features/codex/seccomp/README.md`:

````markdown
# Vendored seccomp profile

`userns.json` is Moby's default seccomp profile with three edits that let
Codex's Bubblewrap-based patch helper create an unprivileged user namespace.
Without them, every Codex edit fails (hube/devcontainer#36).

JSON cannot carry comments, so this file is the record of what was changed and
why.

## Upstream

| | |
|---|---|
| Repository | [`moby/profiles`](https://github.com/moby/profiles) |
| Tag | `seccomp/v0.2.3` |
| File | `seccomp/default.json` |
| SHA-256 | `536529b665dd0972c37bfb569f5d4ac8a53592e7b00752bc39ff063ca9864c74` |

The profile used to live in `moby/moby` at `profiles/seccomp/default.json`.
It does not any more — that path is absent from current Moby release tags, and
the profiles are now published from their own independently versioned
repository.

## Edits

The upstream `defaultAction` is `SCMP_ACT_ERRNO`, so a syscall is denied unless
a rule allows it. The three edits start from different upstream states, which is
why they are described separately:

1. **`mount`, `umount2`, `setns`, `unshare` are ungated.** Upstream allows them
   only when the container holds `CAP_SYS_ADMIN`. They are now allowed
   unconditionally. Bubblewrap needs them *inside* the namespace it creates, and
   the `CAP_SYS_ADMIN` it gains there is invisible to seccomp — Docker compiles
   the filter from the container's bounding capabilities at start time — so
   gating on the capability is equivalent to denying them.
2. **`pivot_root` is newly allowed.** It appears nowhere upstream, so it was
   denied by the default action rather than capability-gated. This genuinely
   widens the allowlist beyond what any capability grants today.
3. **The `clone` argument filter is dropped.** Upstream allows `clone` only when
   `(flags & 0x7e020000) == 0`; that mask is exactly the `CLONE_NEW*` namespace
   bits. Removing the filter is what permits `CLONE_NEWUSER`.

`clone3` is deliberately left alone: upstream returns `ENOSYS` for it without
`CAP_SYS_ADMIN`, which makes glibc fall back to `clone`, where the flag filter
above can actually be enforced. Seccomp cannot inspect `clone3`'s flags (they
sit behind a userspace pointer), so ungating it would open a namespace path that
cannot be filtered at all.

Everything else is unchanged. All other syscalls the default profile denies stay
denied — this is a much narrower relaxation than `seccomp=unconfined`.

## Re-vendoring

Do this when upstream publishes a profile release that adds syscalls the
container needs (the symptom is a new syscall returning `EPERM` for no obvious
reason). Never hand-edit `userns.json`; regenerate it so the diff stays
reviewable.

```bash
TAG=seccomp/v0.2.3   # bump to the release you are moving to
curl -fsSL -o /tmp/default.json \
  "https://raw.githubusercontent.com/moby/profiles/${TAG}/seccomp/default.json"
sha256sum /tmp/default.json   # record this in the table above

jq '
  .syscalls |= (
    map(if (.names | index("clone")) and has("args") then del(.args) else . end)
    + [{"names":["mount","umount2","setns","unshare","pivot_root"],"action":"SCMP_ACT_ALLOW"}]
  )
' /tmp/default.json > userns.json
```

Then review the diff against the previous `userns.json` and run
`../test/test-seccomp-profile.sh`, which checks both the shape of the file and
that Bubblewrap actually works under it.
````

- [ ] **Step 6: Commit**

```bash
set -euo pipefail
.devcontainer/local-features/codex/test/test-seccomp-profile.sh || exit 1
ssh-add -l || exit 1
git status --short --branch || exit 1
git diff --check || exit 1
git diff || exit 1
git add .devcontainer/local-features/codex/seccomp/userns.json \
        .devcontainer/local-features/codex/seccomp/README.md \
        .devcontainer/local-features/codex/test/test-seccomp-profile.sh
git commit -m "$(cat <<'EOF'
Vendor a seccomp profile permitting unprivileged user namespaces

Codex's patch helper runs every edit inside Bubblewrap, which cannot
create a user namespace under Docker's default seccomp profile, so Codex
cannot write files in this container at all (#36).

Vendor moby/profiles seccomp/v0.2.3 with three edits: ungate the
capability-gated mount family, newly allow pivot_root (absent upstream,
so denied by the default action), and drop the clone CLONE_NEW* argument
filter. clone3 keeps its ENOSYS fallback so the namespace path stays
filterable.

The test asserts both the file's shape and its behaviour: the stock
profile must still reproduce #36, and the vendored one must let bwrap run
a sandboxed command.

Harness: <harness>
Harness-Version: <version>
Model: <model id>
Skills: <comma-separated skills actually used; omit this line when none>
Co-Authored-By: <model display name> <noreply address>
EOF
)"
git log -1 --pretty=%B | git interpret-trailers --parse
```

Expected: the parse output lists every trailer. If any is missing, a blank line split the block — amend before continuing.

---

### Task 2: Activate the profile from the feature

**Files:**
- Modify: `.devcontainer/local-features/codex/devcontainer-feature.json`
- Test: `.devcontainer/local-features/codex/test/test-metadata.sh`

**Interfaces:**
- Consumes: the profile path from Task 1.
- Produces: the `securityOpt` entry `seccomp=${localWorkspaceFolder}/.devcontainer/local-features/codex/seccomp/userns.json` in the feature metadata, and the hook path `~/bin/devcontainer-feature/codex/postCreateScript.sh` that Task 3 creates.

**Why this works** (do not "simplify" it away): the Dev Container feature schema permits `securityOpt`; the CLI unions every feature's `securityOpt` into the merged config and passes each as `--security-opt` to `docker run`. Feature metadata goes through the same variable substitution as `devcontainer.json`, so `${localWorkspaceFolder}` resolves to the **host** path of the checkout — which is what `--security-opt seccomp=<path>` needs, because the Docker CLI reads the profile off the host filesystem at container-create time. A container-side path would not work. The image label stores the metadata **unsubstituted**, which is why the test below asserts on the literal `${localWorkspaceFolder}` string.

- [ ] **Step 1: Write the failing test**

Create `.devcontainer/local-features/codex/test/test-metadata.sh`:

```bash
#!/usr/bin/env bash
# Asserts the Codex feature's securityOpt and postCreateCommand actually reach
# the built image's devcontainer.metadata label. A typo in either is silently
# ignored by the CLI, so this must be asserted, never assumed.
#
# The label stores metadata *unsubstituted*, so the expected securityOpt still
# contains the literal ${localWorkspaceFolder}; the CLI resolves it against the
# host checkout when the container is created.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
IMAGE="dc-codex-metadata-assert:$(date +%s)-$$-$RANDOM"
BUILD_LOG="$(mktemp)"
INSPECT_LOG="$(mktemp)"
METADATA="$(mktemp)"
trap 'docker image rm --force "$IMAGE" >/dev/null 2>&1 || true; rm -f "$BUILD_LOG" "$INSPECT_LOG" "$METADATA"' EXIT

fail() {
  local problem=$1 consequence=$2 remedy=$3
  shift 3
  printf 'Problem: %s\nConsequence: %s\nRemedy: %s\n' \
    "$problem" "$consequence" "$remedy" >&2
  while [[ $# -ge 2 ]]; do
    printf '%s said: %s\n' "$1" "${2:-<no output>}" >&2
    shift 2
  done
  exit 1
}

if ! npx -y @devcontainers/cli@latest build \
  --workspace-folder "$REPO_ROOT" --image-name "$IMAGE" >"$BUILD_LOG" 2>&1; then
  fail "The Dev Container image build failed." \
    "The Codex feature metadata cannot be verified in a built image." \
    "Fix the Dev Container build error shown below, then rerun this test." \
    "npx devcontainer build" "$(cat "$BUILD_LOG")"
fi

if ! docker inspect "$IMAGE" --format '{{ index .Config.Labels "devcontainer.metadata" }}' \
  >"$METADATA" 2>"$INSPECT_LOG"; then
  fail "Docker could not inspect the built image's devcontainer.metadata label." \
    "The Codex feature's securityOpt and postCreateCommand cannot be verified." \
    "Fix the Docker inspect error shown below, then rerun this test." \
    "docker inspect stdout" "$(cat "$METADATA")" \
    "docker inspect stderr" "$(cat "$INSPECT_LOG")"
fi

python3 -c '
import json, sys

def fail(problem, consequence, remedy, tool, output):
    print(f"Problem: {problem}", file=sys.stderr)
    print(f"Consequence: {consequence}", file=sys.stderr)
    print(f"Remedy: {remedy}", file=sys.stderr)
    print("{} said: {}".format(tool, output or "<no output>"), file=sys.stderr)
    raise SystemExit(1)

def check(cond, problem, consequence, remedy, output):
    if not cond:
        fail(problem, consequence, remedy, "metadata validation", output)

try:
    meta = json.load(sys.stdin)
except json.JSONDecodeError as exc:
    fail("The built image has a devcontainer.metadata label that is not valid JSON.",
         "The Codex feature metadata cannot be checked for the required security configuration.",
         "Rebuild the image with valid feature metadata, then rerun this test.",
         "python json parser", f"{type(exc).__name__}: {exc}")

check(isinstance(meta, list),
      "The devcontainer.metadata label is not a JSON array.",
      "The Codex feature metadata entry cannot be located reliably.",
      "Rebuild the image so devcontainer.metadata contains the feature metadata array.",
      f"expected a list, got {type(meta).__name__}: {meta!r}")
entries = [e for e in meta if isinstance(e, dict) and e.get("id") == "./local-features/codex"]
check(len(entries) == 1,
      "The built image does not contain exactly one Codex feature metadata entry.",
      "The Codex feature security configuration cannot be selected unambiguously.",
      "Ensure the Codex feature is declared exactly once, rebuild the image, and rerun this test.",
      f"expected exactly one codex metadata entry, got {len(entries)}")
codex = entries[0]

expected_opt = ("seccomp=${localWorkspaceFolder}"
                "/.devcontainer/local-features/codex/seccomp/userns.json")
opts = codex.get("securityOpt") or []
check(isinstance(opts, list) and expected_opt in opts,
      "The Codex metadata entry has a missing or incorrect securityOpt.",
      "Docker may start the container without the seccomp profile Codex needs to apply edits.",
      f"Set securityOpt to include {expected_opt!r}, rebuild the image, and rerun this test.",
      f"securityOpt missing or wrong: {opts}")

expected_hook = "~/bin/devcontainer-feature/codex/postCreateScript.sh"
actual_hook = codex.get("postCreateCommand")
check(actual_hook == expected_hook,
      "The Codex metadata entry has a missing or incorrect postCreateCommand.",
      "Container creation may skip the user-namespace smoke test and surface failures mid-session.",
      f"Set postCreateCommand to {expected_hook!r}, rebuild the image, and rerun this test.",
      f"bad postCreateCommand: {actual_hook}")

print("codex securityOpt and postCreateCommand verified")
' <"$METADATA"
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
chmod +x .devcontainer/local-features/codex/test/test-metadata.sh
.devcontainer/local-features/codex/test/test-metadata.sh
```

Expected: the image builds, then the script exits non-zero with the semantic
failure's wrapper-owned diagnostic (problem → consequence → remedy → actual
validator output):

```text
Problem: The Codex metadata entry has a missing or incorrect securityOpt.
Consequence: Docker may start the container without the seccomp profile Codex needs to apply edits.
Remedy: Set securityOpt to include 'seccomp=${localWorkspaceFolder}/.devcontainer/local-features/codex/seccomp/userns.json', rebuild the image, and rerun this test.
metadata validation said: securityOpt missing or wrong: []
```

Build, Docker inspect, JSON parse, and semantic assertion failures each use distinct diagnostics and preserve the failing command's actual output under their own `<command> said:` prefix.

(The build takes a few minutes. If `npx` cannot reach the network, that is an environment problem, not a test failure — resolve it before continuing, since Task 2 cannot be verified without it.)

- [ ] **Step 3: Add `securityOpt` and the hook to the feature**

Modify `.devcontainer/local-features/codex/devcontainer-feature.json`. Keep the existing `id`, `name`, `version`, `dependsOn`, `installsAfter`, and `mounts` exactly as they are; add the two new top-level keys after `mounts`:

```json
{
  "id": "codex",
  "name": "Codex",
  "version": "1.0.0",
  "dependsOn": {
    "ghcr.io/devcontainers/features/sshd:1": {}
  },
  "installsAfter": ["ghcr.io/devcontainers/features/common-utils"],
  "mounts": [
    {
      "type": "volume",
      "source": "codex-code-config-${devcontainerId}",
      "target": "/home/${localEnv:USERNAME:devcontainer}/.codex"
    },
    {
      "type": "bind",
      "source": "${localEnv:HOME}/.claude/CLAUDE.md",
      "target": "/home/${localEnv:USERNAME:devcontainer}/.codex/AGENTS.md"
    }
  ],
  // Codex patches files through Bubblewrap, which needs an unprivileged user
  // namespace that Docker's default seccomp profile denies. See seccomp/README.md.
  "securityOpt": [
    "seccomp=${localWorkspaceFolder}/.devcontainer/local-features/codex/seccomp/userns.json"
  ],
  "postCreateCommand": "~/bin/devcontainer-feature/codex/postCreateScript.sh"
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
.devcontainer/local-features/codex/test/test-metadata.sh
```

Expected: `codex securityOpt and postCreateCommand verified`.

Note: the container is not rebuilt yet, so the hook script does not exist on disk. That is fine — this task asserts the metadata wiring only. Task 3 creates the script.

- [ ] **Step 5: Commit**

```bash
set -euo pipefail
.devcontainer/local-features/codex/test/test-metadata.sh || exit 1
ssh-add -l || exit 1
git status --short --branch || exit 1
git diff --check || exit 1
git diff || exit 1
git add .devcontainer/local-features/codex/devcontainer-feature.json \
        .devcontainer/local-features/codex/test/test-metadata.sh
git commit -m "$(cat <<'EOF'
Activate the seccomp profile from the Codex feature

Declare securityOpt on the feature itself rather than runArgs in
devcontainer.json, so the capability stays scoped to the feature that
needs it. The CLI unions feature securityOpt into the merged config and
passes it to docker run; ${localWorkspaceFolder} resolves to the host
path, which is what --security-opt seccomp=<path> requires.

Also declare the postCreateCommand hook the smoke test will install.

Harness: <harness>
Harness-Version: <version>
Model: <model id>
Skills: <comma-separated skills actually used; omit this line when none>
Co-Authored-By: <model display name> <noreply address>
EOF
)"
git log -1 --pretty=%B | git interpret-trailers --parse
```

---

### Task 3: Install bubblewrap and the create-time smoke test

**Files:**
- Create: `.devcontainer/local-features/codex/bin/devcontainer-feature/codex/postCreateScript.sh`
- Modify: `.devcontainer/local-features/codex/install.sh`
- Test: `.devcontainer/local-features/codex/test/test-postcreate.sh`

**Interfaces:**
- Consumes: the hook path declared in Task 2 (`~/bin/devcontainer-feature/codex/postCreateScript.sh`) — the script must land at exactly that path.
- Produces: nothing later tasks depend on.

**Two things the implementer must not skip:**

1. **Make the `bubblewrap` dependency explicit.** There are two `bwrap` binaries in this container and they must not be confused. Codex's installer vendors its own copy at `~/.codex/packages/<version>/codex-resources/bwrap` — version-scoped, an implementation detail of Codex's release layout, not a stable thing to probe. The system `/usr/bin/bwrap` arrives incidentally: it sits in the `common-utils` feature's `apt-get install` list (verified in this image's apt history, alongside `jq` and `socat`). It *is* therefore present on a fresh build today — but a load-bearing binary reaching us through another feature's incidental package list is a silent dependency, and if that list ever changes the smoke test fails at create time with a confusing `bwrap: command not found`. `install.sh` installs the package explicitly. `apt-get install` on an already-installed package is a no-op, so this costs a cached apt layer and buys a dependency that is visible in the feature that actually needs it.
2. **This hook fails the container create on error.** That is deliberate and differs from `agent-skills`, which never fails start. A Codex feature that cannot run Codex's patch helper is broken, and starting quietly just relocates the failure into the middle of a session — the exact symptom issue #36 reports.

- [ ] **Step 1: Write the failing test**

Create `.devcontainer/local-features/codex/test/test-postcreate.sh`:

```bash
#!/usr/bin/env bash
# Tests postCreateScript.sh's success and failure paths without rebuilding the
# container. The failure path is forced by stubbing `unshare` and `bwrap` on
# PATH, so the test does not depend on the host's namespace policy.
set -uo pipefail

HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/devcontainer-feature/codex/postCreateScript.sh"
passed=0
failed=0

pass() { printf 'ok   %s\n' "$1"; passed=$((passed + 1)); }
fail() { printf 'FAIL %s\n     %s\n' "$1" "$2"; failed=$((failed + 1)); }

[[ -x "$HOOK" ]] && pass "hook: is executable" || fail "hook: is executable" "$HOOK"

run_hook() {
  local dir; dir="$(mktemp -d)"
  printf '#!/usr/bin/env bash\n[[ %s -eq 0 ]] || echo "%s" >&2\nexit %s\n' "$1" "$3" "$1" > "$dir/unshare"
  printf '#!/usr/bin/env bash\n[[ %s -eq 0 ]] || echo "%s" >&2\nexit %s\n' "$2" "$3" "$2" > "$dir/bwrap"
  chmod +x "$dir/unshare" "$dir/bwrap"
  OUT="$(PATH="$dir:$PATH" "$HOOK" 2>&1)"; RC=$?
  rm -rf "$dir"
}

run_hook 0 0 ""
[[ $RC -eq 0 ]] && pass "success: exits 0 when namespaces work" \
  || fail "success: exits 0 when namespaces work" "rc=$RC out=$OUT"

run_hook 1 0 "unshare: Operation not permitted"
[[ $RC -ne 0 ]] && pass "userns blocked: fails the container create" \
  || fail "userns blocked: fails the container create" "exited 0"
[[ "$OUT" == *"user namespace"* ]] && pass "userns blocked: names the problem" \
  || fail "userns blocked: names the problem" "$OUT"
[[ "$OUT" == *"cannot apply edits"* ]] && pass "userns blocked: names the consequence" \
  || fail "userns blocked: names the consequence" "$OUT"

[[ "$OUT" == *"seccomp/userns.json"* && "$OUT" == *"rebuild"* ]] \
  && pass "userns blocked: names the remedy" \
  || fail "userns blocked: names the remedy" "$OUT"
[[ "$OUT" == *"unshare said: unshare: Operation not permitted"* ]] \
  && pass "userns blocked: relays the underlying error" \
  || fail "userns blocked: relays the underlying error" "$OUT"

missing_dir="$(mktemp -d)"
ln -s "$(command -v bash)" "$missing_dir/bash"
ln -s "/usr/bin/true" "$missing_dir/unshare"
OUT="$(PATH="$missing_dir" "$HOOK" 2>&1)"; RC=$?
rm -rf "$missing_dir"
[[ $RC -ne 0 ]] && pass "bwrap missing: fails the container create" || fail "bwrap missing: fails the container create" "exited 0"
[[ "$OUT" == *"Bubblewrap is not installed"* ]] && pass "bwrap missing: names the problem" || fail "bwrap missing: names the problem" "$OUT"
[[ "$OUT" == *"cannot apply edits"* ]] && pass "bwrap missing: names the consequence" || fail "bwrap missing: names the consequence" "$OUT"
[[ "$OUT" == *"bubblewrap package"* && "$OUT" == *"rebuild"* ]] && pass "bwrap missing: names the package remedy" || fail "bwrap missing: names the package remedy" "$OUT"
[[ "$OUT" == *"command -v bwrap said: no output"* ]] && pass "bwrap missing: frames the underlying lookup output" || fail "bwrap missing: frames the underlying lookup output" "$OUT"

run_hook 0 1 "bwrap: No permissions to create a new namespace"
[[ $RC -ne 0 ]] && pass "bwrap blocked: fails the container create" \
  || fail "bwrap blocked: fails the container create" "exited 0"
[[ "$OUT" == *"Bubblewrap"* ]] && pass "bwrap blocked: distinct message from the userns case" \
  || fail "bwrap blocked: distinct message from the userns case" "$OUT"
[[ "$OUT" == *"bwrap said: bwrap: No permissions"* ]] \
  && pass "bwrap blocked: relays the underlying error" \
  || fail "bwrap blocked: relays the underlying error" "$OUT"

INSTALL="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/install.sh"
grep -q 'bubblewrap' "$INSTALL" \
  && pass "install: installs bubblewrap explicitly" \
  || fail "install: installs bubblewrap explicitly" "the hook's bwrap would depend on another feature's package list"

printf '\n%d passed, %d failed\n' "$passed" "$failed"
[[ $failed -eq 0 ]]
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
chmod +x .devcontainer/local-features/codex/test/test-postcreate.sh
.devcontainer/local-features/codex/test/test-postcreate.sh
```

Expected: fails — the hook script does not exist yet, and `install.sh` does not mention `bubblewrap`.

- [ ] **Step 3: Write the smoke test hook**

Create `.devcontainer/local-features/codex/bin/devcontainer-feature/codex/postCreateScript.sh`:

```bash
#!/usr/bin/env bash
# Verifies the seccomp profile this feature ships actually took effect.
set -uo pipefail

PROFILE=".devcontainer/local-features/codex/seccomp/userns.json"

die() {
  local problem="$1" remedy="$2" tool="$3" output="$4"
  {
    echo "codex: $problem"
    echo "codex: Codex's patch helper cannot apply edits, so Codex cannot write files in this container."
    echo "codex: $remedy"
    echo "codex: $tool said: ${output:-no output}"
  } >&2
  exit 1
}

if ! output="$(unshare --user --map-root-user true 2>&1)"; then
  die "creating an unprivileged user namespace is blocked." \
    "Check that the Codex feature's securityOpt resolves to $PROFILE on the host, then rebuild the container." \
    unshare "$output"
fi

if ! bwrap_path="$(command -v bwrap 2>&1)"; then
  die "Bubblewrap is not installed." \
    "Install the bubblewrap package by rebuilding the container with the Codex feature." \
    "command -v bwrap" "$bwrap_path"
fi

if ! output="$(bwrap --unshare-all --dev-bind / / true 2>&1)"; then
  die "Bubblewrap cannot start a sandbox even though user namespaces work." \
    "Check that the Codex feature's securityOpt resolves to $PROFILE on the host, then rebuild the container." \
    bwrap "$output"
fi

exit 0
```

- [ ] **Step 4: Install bubblewrap and the hook**

Modify `.devcontainer/local-features/codex/install.sh`. The script re-execs itself as the container user, so the root-only work (package install, copying files into the user's home) must happen in the first branch, before the `exec sudo`. Replace the file with:

```bash
#!/usr/bin/env bash

# Install OpenAI Codex CLI. Installation script originally copied from
# https://developers.openai.com/codex/cli

set -euo pipefail
CONTAINER_USER="${_CONTAINER_USER:-$(id -un)}"

if [[ $EUID -ne $(id -u "${CONTAINER_USER}") ]]
then
  # Codex patches files through Bubblewrap. This feature owns the dependency
  # rather than inheriting it from common-utils' incidental package list.
  echo ">Installing Bubblewrap"
  apt-get update
  apt-get install -y --no-install-recommends bubblewrap
  rm -rf /var/lib/apt/lists/*

  echo ">Copying config to the remote user's home directory"

  # Copy files over while setting ownership and permissions
  rsync -rp \
      --chown=${CONTAINER_USER}:${CONTAINER_USER} \
      --chmod=D755,F644 \
      home/. "/home/${CONTAINER_USER}"

  # Lifecycle hooks must remain executable.
  rsync -rp \
      --chown=${CONTAINER_USER}:${CONTAINER_USER} \
      --chmod=D755,F755 \
      bin "/home/${CONTAINER_USER}"

  exec sudo -iu "${CONTAINER_USER}" "$(realpath "$0")"
fi

echo ">Switched to the container user"

echo ">Installing Codex CLI"

curl -fsSL https://chatgpt.com/codex/install.sh | CODEX_NON_INTERACTIVE=1 sh

echo ">Done installing Codex CLI"
```

- [ ] **Step 5: Run the test to verify it passes**

```bash
chmod +x .devcontainer/local-features/codex/bin/devcontainer-feature/codex/postCreateScript.sh
.devcontainer/local-features/codex/test/test-postcreate.sh
```

Expected: all assertions `ok`, ending `16 passed, 0 failed`.

The two "relays the underlying error" assertions are the ones that matter most, and they have been checked against a hook *without* the fix: a naive version that prints its own message but swallows the command's stderr fails exactly those two and passes the other diagnostic assertions. That is why they assert on the wrapper's framing (`unshare said: ...`) rather than on the bare error text, which the failing command writes to stderr on its own.

- [ ] **Step 6: Commit**

```bash
set -euo pipefail
.devcontainer/local-features/codex/test/test-postcreate.sh || exit 1
ssh-add -l || exit 1
git status --short --branch || exit 1
git diff --check || exit 1
git diff || exit 1
git add .devcontainer/local-features/codex/bin/devcontainer-feature/codex/postCreateScript.sh \
        .devcontainer/local-features/codex/install.sh \
        .devcontainer/local-features/codex/test/test-postcreate.sh
git commit -m "$(cat <<'EOF'
Verify user namespaces at container create

Install bubblewrap explicitly rather than inherit it from common-utils'
package list, and add a postCreate hook that probes unshare and bwrap.
The hook fails the create rather than starting quietly: a Codex feature
whose patch helper cannot run is broken, and coming up anyway would just
relocate the failure into the middle of a session.

Harness: <harness>
Harness-Version: <version>
Model: <model id>
Skills: <comma-separated skills actually used; omit this line when none>
Co-Authored-By: <model display name> <noreply address>
EOF
)"
git log -1 --pretty=%B | git interpret-trailers --parse
```

---

### Task 4: Document the feature

**Files:**
- Create: `.devcontainer/local-features/codex/NOTES.md`
- Modify: `README.md`
- Modify: `docs/designs/2026-07-11-codex-bwrap-user-namespaces-design.md`

**Interfaces:**
- Consumes: everything from Tasks 1-3.
- Produces: nothing.

There is no automated test here; the check is that the documented behaviour matches what Tasks 1-3 actually built.

- [ ] **Step 1: Write NOTES.md**

Create `.devcontainer/local-features/codex/NOTES.md`, following the Behavior / Failure handling / Caveats structure of `agent-skills/NOTES.md`:

```markdown
## Behavior

This feature installs the Codex CLI, and configures the container so Codex can
actually edit files in it.

Codex applies every patch inside a [Bubblewrap][1] sandbox, which has to create
an unprivileged user namespace. Docker's default seccomp profile denies that, so
without this configuration Codex fails on its first edit and cannot write
anything (hube/devcontainer#36).

The feature therefore ships its own seccomp profile, `seccomp/userns.json`, and
activates it through its own `securityOpt`. Nothing needs to be added to
`devcontainer.json` — no `runArgs`, no `--security-opt`. Installing this feature
is the whole configuration.

The profile is read **from the host** when the container is created, so the
feature has to be referenced by relative path (`./local-features/codex`) from a
checkout of this repository. That is how `devcontainer.json` already consumes it.
The path travels with the feature, so the two cannot drift apart.

`seccomp/README.md` records where the profile came from, exactly what was changed
relative to upstream, and how to re-vendor it.

## Failure handling

On container create the feature probes the capability it depends on: it creates
a user namespace with `unshare`, then starts a Bubblewrap sandbox. If either
fails, **container create fails**, naming the problem, the consequence, the
remedy, and the underlying error.

This is deliberately stricter than the `agent-skills` feature, which never fails
container start. A Codex feature whose patch helper cannot run is not degraded,
it is broken — and starting quietly would only move the failure into the middle
of a Codex session, which is the symptom that made the original bug so confusing.

The feature installs the `bubblewrap` package itself. `common-utils` happens to
install it too, but a binary this feature cannot work without should not arrive
as a side effect of another feature's package list.

## Caveats

The seccomp relaxation is container-wide, not Codex-specific: any process in the
container can create user namespaces and call the mount-family syscalls. It is
still far narrower than `seccomp=unconfined` — every other syscall the default
profile denies stays denied — but it is a real widening, and it is the price of
running a sandboxing tool inside a sandbox.

The profile is only known to be needed on Docker Desktop hosts. On Linux hosts
with AppArmor (Ubuntu 23.10+), unprivileged user namespaces are restricted by
AppArmor as well, and seccomp alone would not be enough.

[1]: https://github.com/containers/bubblewrap
```

- [ ] **Step 2: Link it from the root README**

Modify `README.md`. After the existing `agent-skills` paragraph, add:

```markdown
The [`codex`](.devcontainer/local-features/codex/NOTES.md) local feature installs
the Codex CLI and ships the seccomp profile Codex's Bubblewrap sandbox needs in
order to patch files.
```

- [ ] **Step 3: Update the design document's status**

Modify `docs/designs/2026-07-11-codex-bwrap-user-namespaces-design.md`.

Replace the status line:

```markdown
**Status:** Design approved; implementation plan under review in PR #40.
```

with:

```markdown
**Status:** Implemented. Plan:
`docs/implementation-plans/2026-07-12-codex-bwrap-user-namespaces-implementation-plan.md`.
```

Then sharpen one sentence. The design says the smoke test uses a system `bwrap`
"already present in the image". That is true — `common-utils` installs the
`bubblewrap` package — but it undersells why Task 3 installs it again. Replace
that sentence in section 4 with:

```markdown
The test uses the system `bwrap`. It reaches the image through `common-utils`'s
package list, but the Codex feature installs `bubblewrap` explicitly rather than
inherit a load-bearing binary from another feature's incidental dependencies.
Codex also bundles its own `bwrap` under `~/.codex`, which the test deliberately
ignores: that path is version-scoped to Codex's release layout, and both
binaries hit the same kernel/seccomp boundary, so the system one is a faithful
proxy.
```

- [ ] **Step 4: Verify the docs match what was built**

```bash
set -euo pipefail
if grep -n "runArgs" .devcontainer/devcontainer.json; then
  echo "ERROR: devcontainer.json contains runArgs; seccomp would no longer be feature-owned." >&2
  echo "Remedy: remove the runArgs change and keep securityOpt in the Codex feature." >&2
  exit 1
else
  echo "OK: devcontainer.json untouched"
fi
test -f .devcontainer/local-features/codex/NOTES.md && echo "OK: NOTES.md exists"
grep -q "codex" README.md && echo "OK: README links the feature"
```

Expected: all three `OK` lines. The first matters most — the whole point of this design was that `devcontainer.json` never learns about seccomp.

- [ ] **Step 5: Commit**

```bash
set -euo pipefail
if grep -n "runArgs" .devcontainer/devcontainer.json; then
  echo "ERROR: devcontainer.json contains runArgs; seccomp would no longer be feature-owned." >&2
  echo "Remedy: remove the runArgs change and keep securityOpt in the Codex feature." >&2
  exit 1
else
  echo "OK: devcontainer.json untouched"
fi
test -f .devcontainer/local-features/codex/NOTES.md && echo "OK: NOTES.md exists"
grep -q "codex" README.md && echo "OK: README links the feature"
ssh-add -l || exit 1
git status --short --branch || exit 1
git diff --check || exit 1
git diff || exit 1
git add .devcontainer/local-features/codex/NOTES.md README.md \
        docs/designs/2026-07-11-codex-bwrap-user-namespaces-design.md
git commit -m "$(cat <<'EOF'
Document the Codex feature's seccomp configuration

Add NOTES.md covering what the feature configures, why container create
fails when user namespaces are unavailable, and the security trade-off.
Link it from the README, and correct the design doc's claim that the base
image ships bwrap -- it does not, which is why install.sh now installs it.

Harness: <harness>
Harness-Version: <version>
Model: <model id>
Skills: <comma-separated skills actually used; omit this line when none>
Co-Authored-By: <model display name> <noreply address>
EOF
)"
git log -1 --pretty=%B | git interpret-trailers --parse
```

---

## Final verification

After all four tasks, run the feature's tests together:

```bash
failed=0
for t in .devcontainer/local-features/codex/test/test-*.sh; do
  echo "=== $t"
  "$t" || { echo "FAILED: $t"; failed=1; }
done
exit "$failed"
```

Expected: every script ends `N passed, 0 failed` (or prints its verification line), and none report `FAILED`.

Then the end-to-end check that closes issue #36 — it needs a real rebuild, so it cannot be automated in the test scripts:

1. Rebuild the devcontainer (`devcontainer up --workspace-folder . --remove-existing-container`, or "Rebuild Container" in the editor). The create must succeed; the smoke test runs during it.
2. Inside the rebuilt container, confirm the profile is what is actually loaded:
   ```bash
   unshare --user --map-root-user true && echo "userns OK"
   bwrap --unshare-all --dev-bind / / true && echo "bwrap OK"
   ```
3. Run Codex and have it patch a tracked file in a worktree — the original reproduction from issue #36. The edit must persist.
