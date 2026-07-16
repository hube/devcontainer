# Codex unconfined outer runtime implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:subagent-driven-development` to implement this plan task by task.
> Steps use checkbox (`- [ ]`) syntax for tracking.

**Status:** Complete; implementation under review.

**Goal:** Make the published devcontainer image able to run Codex's Linux
Bubblewrap sandbox on Docker Desktop without consumer-side files.

**Architecture:** The Codex Feature embeds self-contained Docker security
options, the empirically minimal capability set, and a post-create health hook
in image metadata. Its installer provides a root-owned setuid system Bubblewrap;
the health hook exercises the current unauthenticated `codex sandbox` surface.
Static, script-level, built-image, controlled runtime, and unrelated-consumer
tests establish the contract before documentation records it.

**Tech stack:** Dev Container Feature JSON, Bash, Python 3 contract tests,
`@devcontainers/cli`, Docker Desktop, OpenAI Codex CLI.

## Global constraints

- Docker Desktop in Linux-container mode is the only supported runtime.
- Feature metadata must declare exactly `seccomp=unconfined` and
  `apparmor=unconfined`; no value may reference `${localWorkspaceFolder}` or
  another host-side support file.
- Codex and the health hook run as the non-root container user.
- Install the distribution `bubblewrap` package and make `/usr/bin/bwrap`
  root-owned with mode `4755` before re-executing the installer as the user.
- Start capability subtraction with `SYS_ADMIN`, `SYS_CHROOT`, `SETUID`,
  `SETGID`, and `SYS_PTRACE`. Retain a capability only when removing it makes
  the same Codex sandbox probe fail and restoring it makes the probe pass.
- The health check must not authenticate or call a model. It must run
  `codex sandbox -P :workspace` in a temporary working directory, create and
  read a marker there, aggregate independent failures, preserve underlying
  output, and clean up before the final aggregate decision. Cleanup failure is
  a health failure and joins the aggregate diagnostics exactly once.
- Runtime-test cleanup must preserve the incoming status, attempt all required
  cleanup, preserve each failing command's output, and return nonzero when any
  required cleanup fails.
- Every Feature-owned error states the problem, consequence, remedy, and
  captured command output in that order.
- The publication workflow remains unchanged; it does not run the probe on its
  native-Linux GitHub Actions runner.
- The repository README contains only a high-level Codex summary and a link;
  the Codex Feature NOTES owns runtime, security, failure, retirement, and
  acceptance details.
- Do not add a firewall, pin Codex or the base image, add a second image, or
  change Docker-outside-of-Docker.
- Each behavior change follows RED-GREEN-REFACTOR and each task ends in a
  signed commit with the repository-required metadata and co-author trailers.

---

### Task 1: Embed the outer runtime and install system Bubblewrap

**Files:**

- Create: `.devcontainer/local-features/codex/test/test-feature-config.py`
- Modify: `.devcontainer/local-features/codex/devcontainer-feature.json`
- Modify: `.devcontainer/local-features/codex/install.sh`

**Interfaces:**

- Produces Feature metadata keys `securityOpt`, `capAdd`, and
  `postCreateCommand` for later image and consumer tests.
- Produces `/usr/bin/bwrap` owned by `root:root` with mode `4755`.
- Uses the full five-capability candidate list until Task 3 replaces it with
  the controlled-subtraction result.

- [x] **Step 1: Write the failing static contract test**

  Create a Python script that loads the Feature JSON, reads the installer, and
  checks these exact initial values:

  ```python
  SECURITY_OPT = ["seccomp=unconfined", "apparmor=unconfined"]
  CAPABILITY_CANDIDATES = [
      "SYS_ADMIN",
      "SYS_CHROOT",
      "SETUID",
      "SETGID",
      "SYS_PTRACE",
  ]
  POST_CREATE_COMMAND = (
      "~/bin/devcontainer-feature/codex/postCreateScript.sh"
  )
  ```

  The test must reject filesystem paths in every `securityOpt` entry and
  require executable installer commands for `apt-get install ... bubblewrap`,
  `chown root:root /usr/bin/bwrap`, `chmod 4755 /usr/bin/bwrap`, and verification
  through `stat`. Add mutation checks that remove each required command from an
  in-memory installer string and prove the assertion helper rejects the
  mutation; a comment containing the same words must not satisfy the helper.

- [x] **Step 2: Run the contract test and verify RED**

  Run:

  ```bash
  python3 .devcontainer/local-features/codex/test/test-feature-config.py
  ```

  Expected: failure because the current manifest lacks `securityOpt`, `capAdd`,
  and `postCreateCommand`, and the installer lacks the Bubblewrap commands.

- [x] **Step 3: Add the initial Feature metadata**

  Add these top-level fields without changing existing dependencies or mounts:

  ```json
  "securityOpt": [
    "seccomp=unconfined",
    "apparmor=unconfined"
  ],
  "capAdd": [
    "SYS_ADMIN",
    "SYS_CHROOT",
    "SETUID",
    "SETGID",
    "SYS_PTRACE"
  ],
  "postCreateCommand": "~/bin/devcontainer-feature/codex/postCreateScript.sh"
  ```

- [x] **Step 4: Install and verify Bubblewrap before user re-execution**

  Add `set -euo pipefail`, validate `_CONTAINER_USER`, and in the root branch:

  ```bash
  apt_output="$(apt-get update 2>&1 && DEBIAN_FRONTEND=noninteractive \
    apt-get install -y bubblewrap 2>&1)" || {
    status=$?
    printf '%s\n' \
      "Codex system Bubblewrap installation failed. Codex cannot create its Linux sandbox. Verify apt sources and rebuild the container. apt said: ${apt_output:-apt exited with status $status without diagnostic output}" >&2
    exit "$status"
  }
  configure_output="$({
    chown root:root /usr/bin/bwrap && chmod 4755 /usr/bin/bwrap
  } 2>&1)" || {
    status=$?
    printf '%s\n' \
      "Codex system Bubblewrap configuration failed. Codex cannot safely create its Linux sandbox. Ensure the container build runs the Feature installer as root, then rebuild. chown/chmod said: ${configure_output:-configuration exited with status $status without diagnostic output}" >&2
    exit "$status"
  }
  bwrap_metadata="$(stat -c '%U:%G %a' /usr/bin/bwrap 2>&1)" || {
    status=$?
    printf '%s\n' \
      "Codex system Bubblewrap verification failed. Codex cannot create its Linux sandbox. Rebuild the container after confirming the bubblewrap package installs /usr/bin/bwrap. stat said: ${bwrap_metadata:-stat exited with status $status without diagnostic output}" >&2
    exit "$status"
  }
  if [[ "$bwrap_metadata" != "root:root 4755" ]]; then
    printf '%s\n' \
      "Codex system Bubblewrap has invalid ownership or mode: $bwrap_metadata. Codex cannot safely create its Linux sandbox. Ensure /usr/bin/bwrap is root:root with mode 4755, then rebuild the container. stat said: $bwrap_metadata" >&2
    exit 1
  fi
  ```

  Retain the existing configuration copy, then re-execute as the container user
  and install Codex exactly once. Wrap the configuration copy, user
  re-execution, and Codex installer so any failure adds the required
  problem/consequence/remedy prefix before the captured command output.

- [x] **Step 5: Verify GREEN and installer syntax**

  Run:

  ```bash
  python3 .devcontainer/local-features/codex/test/test-feature-config.py
  bash -n .devcontainer/local-features/codex/install.sh
  ```

  Expected: both commands exit zero without output.

- [x] **Step 6: Run the existing non-Docker regression suite and commit**

  Run the agent-skills post-start test and all three github-cli-config tests.
  Expected: 30 agent-skills checks and 27 GitHub CLI post-start checks pass;
  both silent contract tests exit zero. Stage only the three Task 1 files and
  create the signed task commit.

### Task 2: Add the Codex sandbox health hook

**Files:**

- Create: `.devcontainer/local-features/codex/bin/devcontainer-feature/codex/postCreateScript.sh`
- Create: `.devcontainer/local-features/codex/test/test-postcreate.sh`
- Modify: `.devcontainer/local-features/codex/install.sh`
- Modify: `.devcontainer/local-features/codex/test/test-feature-config.py`

**Interfaces:**

- Consumes `/usr/bin/bwrap`, `codex`, GNU `timeout`, and the Task 1
  `postCreateCommand` path.
- Returns zero only when Bubblewrap metadata is exactly `root:root 4755` and
  `codex sandbox -P :workspace` creates and reads `codex-sandbox-marker` in its
  temporary working directory.

- [x] **Step 1: Write the failing health-hook tests**

  Build a temporary `PATH` containing executable `stat`, `timeout`, `codex`,
  and `rm` stubs. The success-world `stat` prints `root:root 4755`; the Codex
  stub records arguments, finds the directory after `-C`, writes
  `codex-sandbox-ok` to `codex-sandbox-marker`, and prints the same sentinel.
  Assert success, exact `sandbox -P :workspace -C` arguments, marker readback,
  and cleanup. Add failure worlds for bad metadata, `stat` failure, Codex
  failure, cleanup failure, simultaneous metadata/Codex failure, and combined
  metadata/Codex/cleanup failure. Assert non-zero status, exact diagnostic
  count and order, and problem/consequence/remedy/wrapped-output ordering.

- [x] **Step 2: Run the hook test and verify RED**

  Run:

  ```bash
  bash .devcontainer/local-features/codex/test/test-postcreate.sh
  ```

  Expected: failure because `postCreateScript.sh` does not exist.

- [x] **Step 3: Implement the minimal hook**

  The hook must use `set -uo pipefail`, an `errors=()` array, and a cleanup trap.
  Capture `stat -c '%U:%G %a' /usr/bin/bwrap` output and continue to the Codex
  probe even when metadata is wrong. Create the temporary directory with
  `mktemp -d`; run:

  ```bash
  timeout 30s codex sandbox -P :workspace -C "$workdir" \
    bash -c "printf '%s\\n' codex-sandbox-ok > codex-sandbox-marker && cat codex-sandbox-marker"
  ```

  Capture combined output and status. Require zero status, sentinel output,
  and marker contents. Attempt temporary-workspace cleanup before deciding the
  aggregate result; append its captured failure as a complete one-line
  diagnostic. Print each independent diagnostic once to stderr and exit one
  when the array is non-empty.

  Update the installer to copy `bin` to the container user's home with
  directories and files mode `755`. Extend the static contract to require that
  copy command and mutation-check its removal.

- [x] **Step 4: Verify GREEN and script syntax**

  Run:

  ```bash
  bash .devcontainer/local-features/codex/test/test-postcreate.sh
  bash -n .devcontainer/local-features/codex/bin/devcontainer-feature/codex/postCreateScript.sh
  ```

  Expected: all named health-hook checks pass and syntax checking exits zero.

- [x] **Step 5: Run Task 1 and existing regressions, then commit**

  Re-run the Task 1 Python contract and the existing non-Docker suite. Stage
  only the four Task 2 files and create the signed task commit.

### Task 3: Prove the image boundary and minimize capabilities on Docker Desktop

**Files:**

- Create: `.devcontainer/local-features/codex/test/test-runtime.sh`
- Create: `.devcontainer/local-features/codex/test/test-runtime-cleanup.sh`
- Modify: `.devcontainer/local-features/codex/devcontainer-feature.json`
- Modify: `.devcontainer/local-features/codex/test/test-feature-config.py`

**Interfaces:**

- Consumes the Task 1 installer and Task 2 health hook.
- Produces the final exact `capAdd` list used by Task 4 documentation and
  consumer acceptance.
- Accepts optional `CODEX_RUNTIME_TEST_IMAGE`; otherwise uses a unique
  `codex-runtime-test:<timestamp>-<pid>` tag and removes it through a trap.

- [x] **Step 1: Write the built-image and controlled-runtime test**

  The script must capture build output in a temporary file and print it on
  failure. Build with:

  ```bash
  npx -y @devcontainers/cli@latest build \
    --workspace-folder "$REPO_ROOT" --image-name "$IMAGE"
  ```

  Inspect `devcontainer.metadata` with Python and require the Codex entry's two
  security options, current `capAdd`, post-create command, and absence of any
  filesystem-backed seccomp value. Run `stat` inside the image as the container
  user and require `root:root 4755 /usr/bin/bwrap`.

  Create a temporary wrapper named `bwrap` before `/usr/bin` on `PATH`; it must
  append its arguments to a host-mounted log and `exec /usr/bin/bwrap "$@"`.
  Use the same image, container user, `HOME`, working directory, wrapper, health
  hook, and 45-second timeout for every probe.

  The control supplies all five candidate capabilities but Docker's default
  seccomp/AppArmor settings and must fail. If it passes, stop with a retirement
  diagnostic. The treatment adds both unconfined options and all five candidate
  capabilities and must pass; require the wrapper log to prove Codex selected
  the system executable. For each candidate, rerun the treatment omitting only
  that capability, then rerun the full treatment. Record a capability as
  required only when omission fails and restoration passes. Finally run the
  exact required set and require success.

  Add a focused behavior test for the runtime finalizer using failing Docker
  test doubles rather than real resources. Require successful cleanup to
  preserve zero and nonzero incoming statuses; require volume failure, image
  failure, and simultaneous failures to return nonzero, retain ordered output,
  and attempt every required cleanup operation.

- [x] **Step 2: Run the controlled test and record its empirical result**

  Run the script on the connected Docker Desktop engine. Expected sequence:
  control failure, full treatment success, one omission result and one restored
  success per candidate, final-set success, and system-Bubblewrap selection.
  The output must print one machine-readable line:

  ```text
  REQUIRED_CAPABILITIES=CAP1,CAP2
  ```

  where the names and order are derived solely by the subtraction rule.

- [x] **Step 3: Make the empirical result a failing static expectation**

  Replace `CAPABILITY_CANDIDATES` in the Python contract with
  `EXPECTED_CAP_ADD` containing exactly the ordered names printed by Step 2,
  while keeping the five-name candidate tuple separately for the runtime test.
  Run the Python test. Expected: failure because the manifest still contains
  at least one capability whose omission passed.

- [x] **Step 4: Update the manifest to the final set and verify GREEN**

  Replace `capAdd` with exactly `EXPECTED_CAP_ADD`. Re-run the Python test and
  `test-runtime-cleanup.sh`, then rebuild and rerun `test-runtime.sh`. Expected:
  cleanup behavior passes without Docker resources, metadata reports the final
  set, the control still fails, the final treatment passes, each retained
  capability's omission fails, restoration passes, and the wrapper proves
  system-Bubblewrap selection.

- [x] **Step 5: Run the full repository test suite and commit**

  Run every Feature test, including the existing built-image install-order test,
  the runtime cleanup behavior test, and the Docker Desktop runtime test.
  Preserve the exact controlled-comparison output in the task report, including
  the benign explanation ruled out: all probes used the same image, command,
  user, and working directory. Stage the four Task 3
  files and create the signed task commit.

### Task 4: Document the contract and accept an unrelated image consumer

**Files:**

- Create: `.devcontainer/local-features/codex/test/test-documentation.sh`
- Create: `.devcontainer/local-features/codex/test/test-image-consumer.sh`
- Modify: `.devcontainer/local-features/codex/NOTES.md`
- Modify: `README.md`
- Modify: `docs/designs/2026-07-14-codex-unconfined-runtime-design.md`
- Modify: `docs/implementation-plans/2026-07-15-codex-unconfined-runtime-implementation-plan.md`

**Interfaces:**

- Consumes the final manifest capability list and the locally built image from
  Task 3.
- `test-image-consumer.sh IMAGE` creates an unrelated temporary workspace whose
  `devcontainer.json` contains only `image` and
  `appPort: ["127.0.0.1::2222"]`.

- [x] **Step 1: Write the failing documentation contract**

  Require NOTES to name the exact two security options, every final capability,
  `/usr/bin/bwrap`, root ownership and mode `4755`, system-versus-bundled
  selection, the relaxed outer boundary, the Codex inner sandbox, container-wide
  exposure, Docker Desktop-only support, creation and health remedies,
  `securityOpt` merge conflicts, the control retirement signal, and both local
  and post-publication acceptance commands. Require README to link to
  `.devcontainer/local-features/codex/NOTES.md` while rejecting the detailed
  security-option and capability strings there.

- [x] **Step 2: Run the documentation test and verify RED**

  Run:

  ```bash
  bash .devcontainer/local-features/codex/test/test-documentation.sh
  ```

  Expected: failure listing the missing Codex runtime documentation.

- [x] **Step 3: Update NOTES and README, then verify GREEN**

  Keep the existing remote-control SSH section in NOTES. Add sections for the
  supported runtime, exact outer runtime settings, system Bubblewrap and inner
  sandbox, consequences for non-Codex processes, conflicting consumer
  `securityOpt`, failure remedies, retirement signal, and acceptance. Add only
  one README sentence: the image includes Codex, with a link to the Feature
  NOTES. Re-run the documentation test and require zero status.

- [x] **Step 4: Write the unrelated-consumer acceptance test**

  The script must require one image argument, create and clean a temporary
  workspace, run `devcontainer up`, preserve its full output on failure, and
  use `devcontainer exec` to initialize a tracked file. Inside the container,
  run `codex sandbox -P :workspace` with the Codex-provided `apply_patch`
  helper to change the file, then require `git diff --exit-code` to fail and
  `git diff --check` to pass. Remove the created container and temporary Docker
  volumes through cleanup traps. Its success output names the image and states
  that post-create health and sandboxed patch persistence were verified.

- [x] **Step 5: Verify the local image consumer and publication command**

  Run Task 3 with a stable temporary tag, then pass that tag to
  `test-image-consumer.sh`. Expected: the unrelated config starts, its embedded
  post-create health hook passes, and the sandboxed patch persists. NOTES must
  also give the post-publication command using
  `ghcr.io/hube/devcontainer:latest`; do not claim issue #36 is resolved until
  that command is run after merge and publication.

- [x] **Step 6: Update artifact status and run final verification**

  Change the design status to `Approved; implementation complete and under
  review.` and this plan status to `Complete; implementation under review.` Run
  every Feature test, JSON parsing, Bash syntax checks for every changed shell
  file, `git diff --check`, the Docker Desktop runtime matrix, and the unrelated
  consumer test. Stage only the six Task 4 files and create the signed task
  commit.

---

## Final branch gate

- [ ] Generate a whole-branch review package from merge base `81e8e6b` through
  branch HEAD and obtain an independent spec-and-quality review.
- [ ] Resolve every Critical or Important finding through a reviewed fix cycle.
- [ ] Re-run the complete static, script, built-image, controlled-runtime, and
  unrelated-consumer verification on the final commit.
- [ ] Publish one PR containing this plan and all implementation commits; assign
  `hube` and monitor its checks.
