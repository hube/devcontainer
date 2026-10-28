# Accept skills startup changes

The Feature owns clone/ref-refresh and independent installer calls. The
agent-skills repository owns installation. Check caller wiring with subprocess
stubs, then run the real installer in disposable consumer homes. These homes
exercise installed state inside the running container; they do not rebuild an
image or reload a running harness session.

## Check the caller

From this repository's root, with Node.js 24 or later and npm available, run:

```bash
npm ci
npm run typecheck
npm run lint
npm test
npm run build
git diff --exit-code -- \
  .devcontainer/local-features/git-commit-attribution/dist/ \
  .devcontainer/local-features/jq/dist/ \
  .devcontainer/local-features/agent-skills/bin/devcontainer-feature/agent-skills/install-skills.cjs \
  scripts/accept-agent-skills.mjs
```

The comparison is against the committed bundles in the checked-out revision; a
nonzero diff means generated output is stale. The focused caller suite is:

```bash
npx vitest run tests-vitest/agent-skills.test.ts
```

It stubs `spawnSync`, not the maintained installer or harness runtime, and checks
explicit targets, independent failures, captured output and non-blocking
completion. Hosted CI also runs local-feature shell suites; the commands above
are the Node gates and affected caller checks.

## Prepare the real installer prerequisites

Run acceptance inside a container with the Feature's SSH forwarding available,
both harness CLIs, Node.js 24 or later, npm, and Git. Check
these prerequisites as the container user:

```bash
node --version
claude --version
codex --version
ssh-add -l
git ls-remote git@github.com:hube/agent-skills.git HEAD
```

If the agent is reachable but empty, run `ssh-add` on the host and restart the
container. If it is unreachable, follow the
[socket-provider diagnosis and restoration](../codex/NOTES.md#retrieve-authorized-task-inputs),
then repeat these checks; that procedure distinguishes Docker Desktop from a
desktop-supplied socket. If the remote check fails, repair the network or
repository access identified in its output before acceptance. No real configuration or authentication is copied
into the disposable homes.

## Run installed-state acceptance

From this repository's root, run:

```bash
node scripts/accept-agent-skills.mjs git@github.com:hube/agent-skills.git
```

The optional second argument selects a source revision available in that remote,
for example `main` or a full commit SHA. A local repository path can replace the
Git URL when an authorized pinned input is already available. The command prints
the selected full SHA and actual CLI versions. It creates a checked temporary
root and retains its command log and disposable consumers there; it performs no
recursive cleanup. A failed prerequisite or assertion exits nonzero, prints the
underlying output and leaves evidence for diagnosis.

The command supplies all fixture inputs itself:

- Each consumer gets its own `HOME`, `CODEX_HOME` and `CLAUDE_CONFIG_DIR`, plus a
  copy of this Feature's hook/helper under its `~/bin`.
- It writes `~/.config/devcontainer-feature/agent-skills.env`, the options file
  normally produced by Feature installation. `AGENT_SKILLS_REPO` points to its
  pinned local bare remote; `AGENT_SKILLS_CLONE_DIR` sets the disposable clone.
- Fresh startup begins with that clone absent. Existing startup first clones
  the input and runs `bash "$clone/setup.sh" claude` and
  `bash "$clone/setup.sh" codex`. Both consumers then run the normal hook twice.
- Protected inputs are synthetic Claude settings, Codex authentication/history
  files and unrelated TOML configuration. The comparator checks exact file bytes
  and the protected TOML prefix while allowing the installer's appended managed
  tables. It must reject an actually altered settings file and accept restoration.
- Separate conflict consumers create a user-owned file at the Claude plugin-link
  path, or register another local checkout as the `hube-agent` Codex marketplace.
  The checks require the conflict to remain intact and the other harness to
  install successfully.

For every successful target, readback checks the Claude link, Codex marketplace
root and plugin installed/enabled state. It also checks an existing clone's HEAD
is unchanged. The command uses the real harness CLIs throughout; its local bare
Git source avoids fetching another revision during a consumer's startup. It
checks state rather than treating the hook's zero exit as installation success.

Reconcile [NOTES.md](NOTES.md) with the exercised behavior and report any unrun
image-rebuild or session-reload acceptance separately from installed-state results.
