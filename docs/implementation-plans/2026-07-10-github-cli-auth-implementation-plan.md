# GitHub CLI Auth Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persist GitHub CLI credentials in a devcontainer-specific Docker volume, bootstrapped from runtime GH_TOKEN or GITHUB_TOKEN so all container processes can use stored gh authentication.

**Architecture:** Retain the official `github-cli` feature as the `gh` binary provider. Add a `github-cli-config` local feature that depends on it, mounts `gh` configuration, and installs a non-fatal user post-start hook. The hook prefers `GH_TOKEN`, otherwise `GITHUB_TOKEN`, clears both token variables for its `gh` child process, and persists the selected credential.

**Tech Stack:** Dev Containers local Features, Bash, GitHub CLI, Python 3, Docker, Dev Container CLI.

Design: docs/designs/2026-07-09-github-cli-auth-design.md

## Global Constraints

- Every warning states the problem, then its consequence, then its remedy.
- A failed command's captured diagnostic output appears inside the wrapper warning.
- Token values travel only on standard input and never appear in arguments, diagnostics, or persisted test output.
- Missing tokens, a missing `gh` executable, and rejected credentials remain non-fatal startup conditions.
- Generic uses of the word "feature" are lowercase.
- Local feature author documentation is stored in `NOTES.md`; `README.md` is reserved for generated feature documentation.
- Classic personal access tokens used with `gh auth login --with-token` require `repo`, `read:org`, and `gist`.
- JSONC parsing supports line comments, block comments, and trailing commas without a new dependency.

---

## Tasks

### Task 1: Hook and hermetic tests

- Create the local post-start hook and a temporary HOME/PATH stub-gh test. Assert no-token no-op/warning, GITHUB_TOKEN fallback, GH_TOKEN precedence, stdin-only token delivery, both token variables unset for gh, no token in arguments, and non-fatal login failure.
- Implement the hook: choose non-empty GH_TOKEN, otherwise GITHUB_TOKEN; when neither exists warn and exit zero; otherwise pipe the selected token to gh auth login with hostname github.com, with-token, insecure-storage, and both environment token variables removed.
- Run bash -n and the test harness; then review, SSH-sign, commit, and validate required trailers.

### Task 2: Feature packaging and devcontainer wiring

- Add a github-cli-config Feature manifest with the official github-cli dependency, a devcontainer-specific ~/.config/gh volume, and the exact post-start hook path.
- Add an installer that validates _CONTAINER_USER and copies bin into that user's home with executable ownership/modes.
- Add a Python json static test for manifest fields, official dependency, mount, hook, both remoteEnv token values, containerEnv.TZ, absent remoteEnv.TZ, and absent Codex shell_environment_policy.
- Wire the local Feature alphabetically after direnv; retain tokens only in remoteEnv and move TZ to containerEnv. Run syntax/static checks, then commit and validate trailers.

### Task 3: Code review fixes

- Seed both `~/.config` and `~/.config/gh` user-owned in the installer, since `install -d` applies ownership only to the directories it is told to create and a root-owned `~/.config` blocks other user tooling.
- Declare `installsAfter` common-utils in the Feature manifest, document `GITHUB_TOKEN` alongside `GH_TOKEN` in the devcontainer `secrets` metadata, and make the static test tolerate JSONC comments in devcontainer JSON files.
- Cover the missing-`gh` startup path in the hermetic tests, and document in the README and design: credential scope (`gh` subcommands only, no `gh auth setup-git`), classic-token minimum scopes, and stale stored-token removal.

### Task 4: Actionable startup warnings

**Files:**
- Modify: `.devcontainer/local-features/github-cli-config/test/test-poststart.sh`
- Modify: `.devcontainer/local-features/github-cli-config/bin/devcontainer-feature/github-cli-config/postStartScript.sh`
- Modify: `docs/designs/2026-07-09-github-cli-auth-design.md`

**Interfaces:**
- Consumes: `GH_TOKEN` and `GITHUB_TOKEN` runtime bootstrap inputs.
- Produces: non-fatal, stderr-only warnings containing captured diagnostics in problem/consequence/remedy order.

- [ ] **Step 1: Write failing wrapper-level tests**

Make the stub emit `GH_ERROR="gh said: token rejected"` on stderr. Require the wrapper-owned form `github-cli-config: GitHub CLI authentication failed: gh said: token rejected.`, followed by `Stored GitHub CLI authentication was not updated.` and `Verify the token is valid and includes repo, read:org, and gist; then restart the container.` Add equivalent three-part assertions for unset/empty tokens and missing `gh`; the missing-executable remedy says to ensure the `github-cli` feature is installed and rebuild the container.

- [ ] **Step 2: Run the hook suite and verify RED**

Run `bash .devcontainer/local-features/github-cli-config/test/test-poststart.sh`.

Expected: the new wrapper assertion fails because raw `gh` stderr is not captured into the generic warning.

- [ ] **Step 3: Capture diagnostics and implement specific warnings**

Capture combined output and preserve the pipeline status:

```bash
gh_output="$(
  printf '%s\n' "$selected_token" | env -u GH_TOKEN -u GITHUB_TOKEN gh auth login \
    --hostname github.com --with-token --insecure-storage 2>&1
)"
gh_status=$?
```

Flatten embedded newlines with `gh_error="${gh_output//$'\n'/; }"`. If the diagnostic is empty, substitute `gh auth login exited with status $gh_status without diagnostic output`. Exit status 127 produces the missing-executable problem and rebuild remedy; other failures produce the rejected-token problem and token verification remedy. The no-token warning names the missing bootstrap input, says stored authentication was not updated, and tells the user to set a token on the host and restart.

- [ ] **Step 4: Verify GREEN**

Run:

```bash
bash .devcontainer/local-features/github-cli-config/test/test-poststart.sh
bash -n .devcontainer/local-features/github-cli-config/bin/devcontainer-feature/github-cli-config/postStartScript.sh .devcontainer/local-features/github-cli-config/test/test-poststart.sh
```

Expected: all hook assertions pass and both scripts are syntactically valid.

- [ ] **Step 5: Synchronize and commit**

Update the design error contract to say diagnostics are captured inside warnings and missing-executable/rejected-token remedies differ. Set status to owner-review fixes in progress. Stage only task files, commit with required metadata/co-author trailers, and verify them with `git interpret-trailers --parse`.

### Task 5: Feature notes, JSONC parsing, and configuration order

**Files:**
- Rename: `.devcontainer/local-features/github-cli-config/README.md` to `.devcontainer/local-features/github-cli-config/NOTES.md`
- Modify: `.devcontainer/local-features/github-cli-config/test/test-documentation.sh`
- Modify: `.devcontainer/local-features/github-cli-config/test/test-feature-config.py`
- Modify: `.devcontainer/devcontainer.json`
- Modify: `README.md`
- Modify: `docs/designs/2026-07-09-github-cli-auth-design.md`
- Modify: `docs/implementation-plans/2026-07-10-github-cli-auth-implementation-plan.md`

**Interfaces:**
- Consumes: JSONC-formatted devcontainer configuration and the GitHub CLI `--with-token` contract.
- Produces: generated-README-safe notes, accurate PAT guidance, dependency-free JSONC parsing, and stable configuration ordering.

- [ ] **Step 1: Write failing documentation and parser tests**

Require `NOTES.md`, lowercase generic `feature`, an explicit classic-PAT preference, and `repo`, `read:org`, and `gist`. Add a test for this exact JSONC contract:

```python
source = r'''{
  // whole-line comment
  "url": "https://example.test/a//b", /* block comment */
  "marker": ",}",
  "items": ["/* literal */",], // inline comment
}'''
assert load_jsonc(source) == {
    "url": "https://example.test/a//b",
    "marker": ",}",
    "items": ["/* literal */"],
}
```

- [ ] **Step 2: Verify RED**

Run the documentation and Python static tests. Expected: documentation fails because `NOTES.md` and complete scope guidance are absent; the parser test fails because the current loader removes whole-line comments only.

- [ ] **Step 3: Implement JSONC parsing without dependencies**

Add `load_jsonc(text: str) -> dict`, backed by string-aware scanners that remove `//` and `/* ... */` comments, preserve newlines, and remove trailing commas only outside strings before `}` or `]`. Track escape state so literal comment markers and `,}`/`,]` strings survive. Keep file I/O separate:

```python
def load_json(path: Path) -> dict:
    return load_jsonc(path.read_text(encoding="utf-8"))
```

- [ ] **Step 4: Rename and revise documentation**

Rename `README.md` to `NOTES.md`; update all references and lowercase generic "feature" uses in the notes, root README, design, plan, and test descriptions. Generalize plaintext storage: the feature always selects plaintext storage, does not detect or integrate with a system credential store, and may support devcontainers with usable Secret Service/keyring sessions later. Make classic PATs the prominent recommendation and list all three minimum permissions before the fine-grained-token caveat.

- [ ] **Step 5: Reorder configuration and synchronize status**

Move the existing `containerEnv` object before `remoteEnv` without changing values. Update the design/plan for `NOTES.md`, all scopes, and full JSONC tolerance; set design status back to `Implemented` after review fixes are complete.

- [ ] **Step 6: Verify GREEN and commit**

Run:

```bash
python3 .devcontainer/local-features/github-cli-config/test/test-feature-config.py
bash .devcontainer/local-features/github-cli-config/test/test-documentation.sh
bash .devcontainer/local-features/github-cli-config/test/test-poststart.sh
bash -n .devcontainer/local-features/github-cli-config/install.sh .devcontainer/local-features/github-cli-config/bin/devcontainer-feature/github-cli-config/postStartScript.sh .devcontainer/local-features/github-cli-config/test/test-poststart.sh .devcontainer/local-features/github-cli-config/test/test-documentation.sh
```

Expected: every suite passes and all Bash files are syntactically valid. Stage only task files, commit with required metadata/co-author trailers, and verify them with `git interpret-trailers --parse`.
