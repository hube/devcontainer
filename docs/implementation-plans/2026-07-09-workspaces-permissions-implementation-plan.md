# Workspaces Permissions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a local Dev Container Feature that makes the image-layer `/workspaces` directory writable by the configured container user so sibling project directories can be created.

**Architecture:** Implement a focused local Feature named `workspaces-permissions` that runs during Feature installation as root, validates `_CONTAINER_USER`, and sets metadata only on `/workspaces` using `install -d`. Wire the Feature into `.devcontainer/devcontainer.json`, document the intended normal-case behavior in `README.md`, and verify behavior in a rebuilt devcontainer.

**Tech Stack:** Dev Containers local Features, Bash, Ubuntu base image, existing `devcontainer.json` Feature configuration.

## Global Constraints

- Target only the normal case where `/workspaces` is the image/container filesystem path.
- Supporting downstream configurations that mount a volume over `/workspaces` itself is explicitly out of scope.
- Do not recursively change ownership under `/workspaces`.
- Do not hardcode the username as `devcontainer`; use `_CONTAINER_USER`.
- Use `install -d -o "${_CONTAINER_USER}" -g "${_CONTAINER_USER}" -m 0755 /workspaces` rather than separate `mkdir`, `chown`, and `chmod` calls.
- Follow the repo's existing local Feature pattern under `.devcontainer/local-features/`.
- Keep design docs and README content in sync with implementation behavior.
- Before each commit in this devcontainer, run `ssh-add -l` and verify an identity is available for SSH commit signing.
- Every commit must include `Harness`, `Harness-Version`, `Model`, `Skills` when skills contributed, and `Co-Authored-By` trailers in one contiguous trailer block.

---

## File Structure

- Create `.devcontainer/local-features/workspaces-permissions/devcontainer-feature.json`: local Feature manifest with id, name, version, and install ordering after `common-utils`.
- Create `.devcontainer/local-features/workspaces-permissions/install.sh`: root-phase installer that validates `_CONTAINER_USER` and sets `/workspaces` ownership/mode without recursion.
- Modify `.devcontainer/devcontainer.json`: include `./local-features/workspaces-permissions` in the existing `features` object.
- Modify `README.md`: document that the normal image-layer `/workspaces` parent is writable by the configured container user, and that mount-over-`/workspaces` configurations manage their own mount permissions.

### Task 1: Add the `workspaces-permissions` local Feature

**Files:**
- Create: `.devcontainer/local-features/workspaces-permissions/devcontainer-feature.json`
- Create: `.devcontainer/local-features/workspaces-permissions/install.sh`

**Interfaces:**
- Consumes: `_CONTAINER_USER` environment variable provided by the Dev Containers Feature installation environment.
- Produces: A local Feature id `workspaces-permissions` that can be referenced from `.devcontainer/devcontainer.json` as `"./local-features/workspaces-permissions": {}`.

- [ ] **Step 1: Verify the Feature does not exist yet**

Run:

```bash
test ! -e .devcontainer/local-features/workspaces-permissions
```

Expected: exit 0. If this exits nonzero, inspect the existing directory before continuing because the implementation may already be partially present.

- [ ] **Step 2: Create the Feature directory and manifest**

Create `.devcontainer/local-features/workspaces-permissions/devcontainer-feature.json` with exactly:

```json
{
  "id": "workspaces-permissions",
  "name": "Workspace parent directory permissions",
  "version": "1.0.0",
  "installsAfter": ["ghcr.io/devcontainers/features/common-utils"]
}
```

- [ ] **Step 3: Create the install script**

Create `.devcontainer/local-features/workspaces-permissions/install.sh` with exactly:

```bash
#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${_CONTAINER_USER:-}" ]] || ! id "${_CONTAINER_USER}" >/dev/null 2>&1; then
  echo "Container user '${_CONTAINER_USER:-}' does not exist" >&2
  exit 1
fi

install -d -o "${_CONTAINER_USER}" -g "${_CONTAINER_USER}" -m 0755 /workspaces
```

- [ ] **Step 4: Make the install script executable**

Run:

```bash
chmod 755 .devcontainer/local-features/workspaces-permissions/install.sh
```

Expected: exit 0.

- [ ] **Step 5: Verify script syntax**

Run:

```bash
bash -n .devcontainer/local-features/workspaces-permissions/install.sh
```

Expected: exit 0 with no output.

- [ ] **Step 6: Verify the missing-user guard fails clearly**

Run:

```bash
if _CONTAINER_USER=__missing_workspaces_user__ bash .devcontainer/local-features/workspaces-permissions/install.sh 2>/tmp/workspaces-permissions.err; then
  echo "expected missing-user guard to fail" >&2
  exit 1
fi
grep -F "Container user '__missing_workspaces_user__' does not exist" /tmp/workspaces-permissions.err
```

Expected: exit 0, and `grep` prints:

```text
Container user '__missing_workspaces_user__' does not exist
```

- [ ] **Step 7: Verify the manifest contains the intended Feature id and install ordering**

Run:

```bash
grep -F '"id": "workspaces-permissions"' .devcontainer/local-features/workspaces-permissions/devcontainer-feature.json
grep -F '"installsAfter": ["ghcr.io/devcontainers/features/common-utils"]' .devcontainer/local-features/workspaces-permissions/devcontainer-feature.json
```

Expected: both `grep` commands exit 0 and print matching lines.

- [ ] **Step 8: Review and commit Task 1**

Run:

```bash
git status --short --branch
git diff -- .devcontainer/local-features/workspaces-permissions/devcontainer-feature.json .devcontainer/local-features/workspaces-permissions/install.sh
ssh-add -l
HARNESS_VERSION="$(codex --version)"
git add .devcontainer/local-features/workspaces-permissions/devcontainer-feature.json .devcontainer/local-features/workspaces-permissions/install.sh
git commit -m "Add workspaces permissions feature" -m "Harness: Codex
Harness-Version: ${HARNESS_VERSION}
Model: gpt-5
Skills: superpowers:subagent-driven-development
Co-Authored-By: GPT-5 <noreply@openai.com>"
git log -1 --pretty=%B | git interpret-trailers --parse
```

Expected: commit succeeds, and the trailer parse output includes `Harness`, `Harness-Version`, `Model`, `Skills`, and `Co-Authored-By` in that order.

### Task 2: Wire the Feature into the devcontainer and README

**Files:**
- Modify: `.devcontainer/devcontainer.json`
- Modify: `README.md`

**Interfaces:**
- Consumes: Feature id and path produced by Task 1: `./local-features/workspaces-permissions`.
- Produces: The devcontainer build includes the new local Feature, and README documents the supported normal-case behavior plus mount-over-`/workspaces` exclusion.

- [ ] **Step 1: Verify the Feature is not already referenced**

Run:

```bash
if grep -F '"./local-features/workspaces-permissions"' .devcontainer/devcontainer.json; then
  echo "workspaces-permissions is already referenced" >&2
  exit 1
fi
```

Expected: exit 0 with no output.

- [ ] **Step 2: Add the local Feature to `.devcontainer/devcontainer.json`**

Modify the `features` object so this section becomes exactly:

```json
    "ghcr.io/devcontainers/features/github-cli:1": {},
    "./local-features/workspaces-permissions": {},
    "./local-features/ccstatusline": {},
    "./local-features/claude": {},
    "./local-features/codex": {},
    "./local-features/direnv": {},
    "./local-features/ssh": {}
```

Keep the rest of `.devcontainer/devcontainer.json` unchanged.

- [ ] **Step 3: Update the README behavior contract**

In `README.md`, replace:

```markdown
Code is mounted in the `/workspaces` dir.
```

with:

```markdown
Code is mounted in the `/workspaces` dir. The devcontainer image makes the
`/workspaces` parent directory writable by the configured container user so that
interactive shells can create sibling project directories, such as
`/workspaces/other-repo`.

Configurations that mount a volume over `/workspaces` itself are responsible for
that mount's permissions.
```

- [ ] **Step 4: Verify the wiring and README text**

Run:

```bash
grep -F '"./local-features/workspaces-permissions": {}' .devcontainer/devcontainer.json
grep -F 'interactive shells can create sibling project directories' README.md
grep -F 'mount a volume over `/workspaces` itself' README.md
```

Expected: all three `grep` commands exit 0 and print matching lines.

- [ ] **Step 5: Review and commit Task 2**

Run:

```bash
git status --short --branch
git diff -- .devcontainer/devcontainer.json README.md
ssh-add -l
HARNESS_VERSION="$(codex --version)"
git add .devcontainer/devcontainer.json README.md
git commit -m "Enable workspaces permissions feature" -m "Harness: Codex
Harness-Version: ${HARNESS_VERSION}
Model: gpt-5
Skills: superpowers:subagent-driven-development
Co-Authored-By: GPT-5 <noreply@openai.com>"
git log -1 --pretty=%B | git interpret-trailers --parse
```

Expected: commit succeeds, and the trailer parse output includes `Harness`, `Harness-Version`, `Model`, `Skills`, and `Co-Authored-By` in that order.

### Task 3: Verify rebuilt devcontainer behavior

**Files:**
- No source changes expected unless verification exposes a bug.

**Interfaces:**
- Consumes: Feature files from Task 1 and devcontainer wiring from Task 2.
- Produces: Evidence that `/workspaces` is writable by the configured container user after rebuild, or a clear note that local verification could not run because the Dev Container CLI is unavailable.

- [ ] **Step 1: Check whether the Dev Container CLI is available**

Run:

```bash
command -v devcontainer
devcontainer --version
```

Expected if local verification is possible: both commands exit 0 and the second prints the installed Dev Container CLI version.

If `command -v devcontainer` fails, skip to Step 5 and record that local rebuilt-container verification could not run in this environment. Do not claim rebuilt-container behavior was verified.

- [ ] **Step 2: Rebuild and start the devcontainer**

Run:

```bash
devcontainer up --workspace-folder .
```

Expected: exit 0. The output should report a built or started devcontainer for this workspace.

- [ ] **Step 3: Verify `/workspaces` ownership and writeability inside the rebuilt container**

Run:

```bash
devcontainer exec --workspace-folder . bash -lc 'set -euo pipefail
id
stat -c "%U:%G %a %n" /workspaces
test -w /workspaces
mkdir /workspaces/test-subdir
rmdir /workspaces/test-subdir'
```

Expected: exit 0. The `stat` output should show the configured container user and group with mode `755`, for example:

```text
devcontainer:devcontainer 755 /workspaces
```

If `${localEnv:USERNAME}` sets a different valid username, the owner and group should match that configured username instead of literal `devcontainer`.

- [ ] **Step 4: Verify the current checkout remains writable**

Run:

```bash
devcontainer exec --workspace-folder . bash -lc 'set -euo pipefail
test -w /workspaces/devcontainer || test -w "$PWD"'
```

Expected: exit 0.

- [ ] **Step 5: Record verification outcome in the implementation PR body**

Use the actual result from Steps 1-4 when opening the implementation PR:

```markdown
## Verification

- `bash -n .devcontainer/local-features/workspaces-permissions/install.sh`
- Missing-user guard check for `_CONTAINER_USER=__missing_workspaces_user__`
- Feature manifest grep checks for `id` and `installsAfter`
- Devcontainer wiring and README grep checks
- Rebuilt devcontainer check when local CLI verification runs:
  - `devcontainer up --workspace-folder .` exited 0.
  - `devcontainer exec --workspace-folder . bash -lc 'set -euo pipefail; id; stat -c "%U:%G %a %n" /workspaces; test -w /workspaces; mkdir /workspaces/test-subdir; rmdir /workspaces/test-subdir'` exited 0.
- Rebuilt devcontainer check when the CLI is unavailable:
  - `command -v devcontainer` exited nonzero, so rebuilt-container verification was not run in this environment.
```

Do not write that rebuilt-container verification passed unless `devcontainer up --workspace-folder .` and the `devcontainer exec --workspace-folder . ...` checks ran and exited 0.

- [ ] **Step 6: Final branch review**

Run:

```bash
git status --short --branch
git log --oneline origin/main..HEAD
git diff origin/main..HEAD -- .devcontainer README.md docs
```

Expected: status is clean, log shows the Task 1 and Task 2 commits, and diff contains only the intended Feature, devcontainer wiring, README update, and implementation plan if it is on the implementation branch.
