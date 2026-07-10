# Git Commit Attribution Design

Status: Draft — awaiting review

## Context

Every AI-authored commit must end with a contiguous trailer block: `Harness`,
`Harness-Version`, `Model`, `Skills`, then `Co-Authored-By` last, with no blank
line splitting it. Today that contract exists only as prose in the host's
`~/.claude/CLAUDE.md`, which reaches Claude Code and Codex through bind mounts.
Nothing checks it.

Two open issues are the same defect seen from opposite ends.

`hube/agent-skills#9` is a **producer** failure. `src/worklog/git.ts` builds a
commit message from a hardcoded template that carries only `Co-Authored-By`, and
pastes a model ID where the display name belongs. No agent misbehaves; the code
predates the contract. It has shipped to production twice (`hube/worklog#33` and
`#36`), and each occurrence required a hand-written history rewrite and a
`--force-with-lease` on an open pull request.

`hube/devcontainer#23` is a **witness** failure. A dispatched subagent reported
that `git log -1 --pretty=%B | git interpret-trailers --parse` showed five
trailers. The commit had four, and the command was never run. Nobody's code was
wrong; the report was. It was caught only because the orchestrator independently
re-derived the answer from git.

Both defects become visible only after the commit exists. That shared property
is what makes a shared control possible.

## Goals

- Make trailer-block compliance a property of the commit, not of an agent's
  memory or honesty.
- Express the contract once, in a place both agents and tooling read.
- Work for any harness. Claude Code today; Codex and other agents next.
- Propagate a contract change to every container without an image rebuild.
- Teach the contract at the moment of violation, to agents that never read it.

## Non-Goals

- Verifying that trailers are **true**. A hook can check that `Model:` is
  present, ordered, and contiguous. It cannot know whether `claude-opus-4-8`
  names the model that actually authored the commit. That remains the
  orchestrator's job.
- Per-repository CI checks on pushed commits. Deferred; see *Bypasses*. A test
  workflow for `hube/devcontainer` itself is in scope; see *Testing*.
- Renaming `hube/claude-home` or the host's `~/.claude` path.

## The Enforcement Point

`git commit` is the only step every agent, every tool, and every human passes
through. Claude Code and Codex share no runtime, no configuration format, and no
environment variables — but both produce commits, and a commit message is a
harness-neutral artifact. A `commit-msg` hook is therefore the one control that
generalizes to agents nobody has configured yet.

This rules out keying enforcement off the environment. `CLAUDECODE` and
`AI_AGENT` are Claude Code's; Codex sets neither. The gate reads the **commit
message** to decide whether a commit claims to be agent-authored.

## Contract Change: `Skills` Becomes Mandatory

The contract currently omits `Skills:` when no skill contributed. That makes the
fabricated message from `hube/devcontainer#23` shape-valid:

```
Harness: Claude Code
Harness-Version: 2.1.205 (Claude Code)
Model: claude-haiku-4-5-20251001
Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>
```

Four trailers, correctly ordered, contiguous. Its only defect is that a skill
*was* used, and nothing in the environment exposes which. A hook cannot detect
this, so the incident that motivated the issue would not be caught by the
mechanism the issue proposed.

`Skills:` therefore becomes mandatory, with an explicit `none` sentinel when
nothing contributed. Omission becomes a shape violation the hook can see. An
agent can still write `Skills: none` untruthfully, but it must now state
something false rather than stay silent — and silence is what actually happened.

This makes some existing compliant messages newly non-compliant, including the
Codex-authored trailer block on `hube/devcontainer#15`. The rollout accounts for
this.

## Architecture

Three artifacts, each on the distribution channel that matches its change rate.

### The spec — `hube/claude-home`

The contract's single source of truth, at `~/.claude/git-commit-attribution.conf`
on the host, reaching containers by bind mount. `CLAUDE.md` points at it and
describes what it means; it does not restate the trailer keys. Keeping the prose
a pointer rather than a copy is a documentation-review rule, not a mechanism —
this design does not enforce it.

```
mode         warn

trailer      Harness           required
trailer      Harness-Version   required
trailer      Model             required
trailer      Skills            required
trailer      Co-Authored-By    required last

agent-author noreply@anthropic.com
agent-author noreply@openai.com
```

One record per line, so the validator needs no parser and no dependency. Two
record types, because the hook needs two things: what must be present, and when
to enforce at all. The `agent-author` list is the harness-neutral trigger, and
extending it for a new provider is a host-side edit rather than an image
rebuild.

`mode` governs whether a violation is an error or a warning. It lives here, on
the fast channel, so promotion and rollback are a `git pull` apart.

Why this repo: dotfiles in `hube/devcontainer-dotfiles` are **copied** into
`$HOME` at container create, so changing one requires a restart. `claude-home`
is bind-mounted, so an edit is live in every running container on the next
commit. The file name is harness-neutral; only the Claude-branded directory
containing it appears in this design, confined to one `source:` line.

### The mechanism — `hube/devcontainer`

A new local Feature, `git-commit-attribution`, harness-neutral and depending on
neither the `claude` nor the `codex` Feature.

```
.devcontainer/devcontainer.json                  (add one stanza)
.devcontainer/local-features/git-commit-attribution/
    devcontainer-feature.json    read-only spec mount; dependsOn node:2
    install.sh                   install bundle; resolve node; write /etc/gitconfig
    dist/commit-msg              committed bundle
    NOTES.md                     the four bypasses, stated plainly
    bin/devcontainer-feature/git-commit-attribution/postStartScript.sh
    test/                        install, postStart, and integration suites

package.json  tsconfig.json  vitest.config.ts  scripts/build.mjs
src/git-commit-attribution/{spec.ts,trailers.ts,validate.ts,cli.ts}
.github/workflows/tests.yml      typecheck, lint, vitest, local-features test/*.sh
```

### The producer — `hube/agent-skills`

`hube/agent-skills#9`. `worklog-contribute` gains a repeatable
`--trailer "Key: value"` flag and stops encoding the contract. The model-ID to
display-name mapping moves to `skills/write-worklog/SKILL.md`, where the
invoking agent already knows both values. `src/worklog/git.ts` no longer builds
a trailer block.

## Container Filesystem

| Path | Provenance | Owner / mode |
| --- | --- | --- |
| `/usr/local/share/git-commit-attribution/hooks/commit-msg` | image layer | `root:root` 0755 |
| `/usr/local/bin/node` → `/usr/local/share/nvm/current/bin/node` | image layer | `root:root` symlink |
| `/etc/gitconfig` (`core.hooksPath`) | image layer | `root:root` 0644 |
| `~/.config/git-commit-attribution/trailer-contract` | read-only bind mount of `${localEnv:HOME}/.claude/git-commit-attribution.conf` | host file |
| `~/bin/devcontainer-feature/git-commit-attribution/postStartScript.sh` | image layer | container user |

The spec is the only piece on the fast channel. Everything else is code, changes
rarely, and rides the image.

The spec is mounted read-only. `local-features/ssh` establishes the
`"type": "bind,readonly"` idiom for `known_hosts`. Read-only matters here because
editing the contract you are about to be judged against would be the easiest
bypass available, and the only one that leaves no trace in the commit.

### Spec Resolution

The hook must not resolve the spec through `~`. `core.hooksPath` lives in system
scope, so the gate also applies to commits made as `root`, whose home directory
is not where the spec is mounted. `install.sh` knows `_CONTAINER_USER`, so it
bakes the absolute path
`/home/${_CONTAINER_USER}/.config/git-commit-attribution/trailer-contract` into
the bundle as it copies it, in the same pass that rewrites the shebang. Every
user in the container then resolves the same spec.

If the host file does not exist, Docker is expected to create a **directory** at
the bind mount's source rather than fail — unverified, and the implementation
must confirm it. Either way the hook must treat a non-file at the spec path as a
missing spec and fail closed, and the postStart warning must name the host path
so a stray directory can be removed and replaced with a real checkout of
`claude-home`.

## Git Config Placement Rule

**Where a Feature writes git config is determined by what happens when the
setting is absent.**

A setting whose absence degrades gracefully goes to user scope, written at
postStart, conditional on its prerequisites, warning and skipping when they are
unmet. That is `~/.config/git/<feature>.inc` with an `include.path` entry in
`~/.gitconfig`.

A setting that is a **control** — where silent absence produces a false belief
that the control is active — goes to system scope, `/etc/gitconfig`, written by
`install.sh` while it still holds root, unconditionally.

The split follows from one question: can the setting's correctness be checked
later, at the moment of use? `core.hooksPath` can — the hook reads the spec at
commit time and fails closed if it is missing. SSH signing config cannot; if the
key is absent, git fails at commit time with no checkpoint that rescues it. So
signing must be conditional and therefore must run at postStart, because
`install.sh` cannot see bind mounts. And `hooksPath` must be unconditional, so
image build is strictly safer.

Consequently:

```ini
# /etc/gitconfig, written by install.sh as root
[core]
	hooksPath = /usr/local/share/git-commit-attribution/hooks
```

`/etc/gitconfig` does not exist in the image today. Git's precedence runs system
< global < local, so the `~/.gitconfig` laid down by `devcontainer-dotfiles` at
container-create time does not disturb it, and a deliberate global
`core.hooksPath` still overrides it per machine.

This Feature has no user-facing setting and writes nothing to `~/.gitconfig`.
The rule is recorded here, and in `NOTES.md`, so that `hube/devcontainer#32` and
its design in `hube/devcontainer#15` inherit a rule rather than a precedent —
and so that no future signing include silently overrides the gate through global
scope.

## Node

The Feature is TypeScript, so every commit in the container depends on a working
node. Three measures make that dependency safe.

The Feature declares `ghcr.io/devcontainers/features/node:2` in its own
`dependsOn`. Node currently reaches this image transitively, as a dependency of
the `ccstatusline` status-line Feature; a commit gate must not inherit its
liveness from a cosmetic Feature.

The hook never consults `PATH`. There is no `/usr/local/bin/node` or
`/usr/bin/node` in the image, and node is nvm-managed, so `node` is on `PATH`
only for processes whose shell sourced a profile — which a hook invoked from an
editor or a daemon may not have done. `install.sh` therefore creates
`/usr/local/bin/node` pointing at `/usr/local/share/nvm/current/bin/node`, a
version-independent symlink that survives node upgrades, and rewrites the
bundle's shebang to that absolute path as it copies. `install.sh` validates the
interpreter is executable and fails the install loudly if not, rather than
deferring the discovery to someone's first commit.

The bundle is **committed**, built by esbuild into a single dependency-free file
using only `node:fs` and `node:child_process`. The image build never runs
`npm install`. One bundle serves both entry points, dispatching on argv:
`commit-msg <msgfile>` when git invokes it, and `--range BASE..HEAD` when CI
runs the committed `dist/commit-msg` directly from a checkout.

Measured node startup in this image is 17–19 ms, negligible beside SSH signing.

If the interpreter is missing despite all of this, git cannot execute the hook
and refuses the commit. The mechanism fails closed by accident, consistent with
its design, though with an unhelpful message.

## Validation Flow

```
commit-msg <msgfile>
  │
  ├─ read spec  ← ~/.config/git-commit-attribution/trailer-contract
  │    missing or malformed → REJECT, naming the path and the offending line
  │
  ├─ trigger?  raw text match on ^(Harness|Harness-Version|Model|Skills):
  │            or ^Co-Authored-By: <address listed as agent-author>
  │    no → exit 0, silently
  │
  ├─ validate: git interpret-trailers --parse <msgfile> → ordered key list
  │    compare against the spec's required sequence
  │
  ├─ mode warn → print the diagnosis, note it will become an error, exit 0
  │
  └─ chain: exec .git/hooks/commit-msg "$msgfile" if executable; its status is ours
```

Two reads of the message, for two different questions.

The **trigger** asks whether the commit claims to be agent-authored, and must
read raw text. A message with a stray prose line above the block parses to zero
trailers, so a trigger based on parsed output would see nothing, decline to
fire, and pass the non-compliant commit. The malformed message would evade the
check precisely because it is malformed.

The **validator** asks whether the claim is well-formed, and delegates entirely
to `git interpret-trailers --parse`. Git's definition of a trailer block is
therefore the contract's definition, and the hook can never disagree with the
`git log -1 --pretty=%B | git interpret-trailers --parse` check the contract
already prescribes. Two properties come free: a blank line inside the block
makes git return only the trailers after it, and a stray line makes git return
nothing. Both surface as missing required trailers.

Commits that trip no trigger pass silently: human-authored commits, GitHub merge
commits, and human-to-human `Co-Authored-By` among them.

**Chaining** is required, not optional. A global `core.hooksPath` shadows every
repository's `.git/hooks/*` entirely. Without chaining, installing this Feature
would silently disable every existing repo hook under `/workspaces`.

## Failure Behavior

The gate fails closed. A `commit-msg` hook that cannot find its contract must not
wave commits through — that is the disease, not the cure.

The `mode` flag lives in the spec, so a missing spec means the hook cannot know
it is in warn mode. **A missing spec rejects, even during warn-only rollout.** A
machine that has not pulled `claude-home` cannot commit anywhere until it does.
The postStart script warns at container start so this is learned before the first
commit, and `--no-verify` is the documented escape.

Rejection messages state the problem, then the consequence, then the remedy, and
carry the contract itself. This message is the primary teaching mechanism: it
reaches an agent that never read `CLAUDE.md`, including a Codex or ChatGPT agent
that nobody configured.

```
git-commit-attribution: commit message is missing the required trailer 'Skills'.
The commit was not created.
Agent-authored commits must end with this contiguous block, Co-Authored-By last:

  Harness: <harness>
  Harness-Version: <version>
  Model: <model id>
  Skills: <skills used, comma-separated, or 'none'>
  Co-Authored-By: <model display name> <noreply address>

Spec: ~/.config/git-commit-attribution/trailer-contract
```

The postStart script never blocks container start, matching the idiom
`local-features/agent-skills/bin/.../postStartScript.sh` establishes. It warns
when the spec mount is absent, and it names any repository under `/workspaces`
whose local `core.hooksPath` shadows the gate.

## Rollout

The gate ships in `mode warn` and is promoted to `mode enforce` by editing the
spec on the host. No rebuild, reversible in seconds.

This ordering matters. The moment `core.hooksPath` is in force,
`worklog-contribute`'s hardcoded message parses to a single `Co-Authored-By`
trailer and would be rejected, so every `/write-worklog` invocation in the
container would fail. Warn mode lets the gate land first and report real
violations against real commits while `hube/agent-skills#9` is fixed.

1. Land the spec and the `CLAUDE.md` pointer in `claude-home`, with `mode warn`.
2. Land the Feature in `devcontainer`, plus `tests.yml`.
3. Fix `hube/agent-skills#9`.
4. Flip `mode enforce` on the host.

## Bypasses

`NOTES.md` states these plainly. Pointing at CI would be dishonest: `claude-home`
and `hube/worklog` have no workflows at all, and `hube/devcontainer` has only
`publish.yaml`.

- **A repository with its own `core.hooksPath`.** Local config outranks global,
  so husky, lefthook, and pre-commit silently bypass the gate. Bypassed by
  accident, with no output. Not fixable from global config. postStart names such
  repositories at container start.
- **`git commit --no-verify`.** One flag. Also the documented escape hatch when
  the spec is broken.
- **Commits made outside the container.** No gate at all.
- **`GIT_CONFIG_NOSYSTEM=1`.** Disables system config and therefore the gate.

The gate is a strong control against honest error — a tool with a hardcoded
message, an agent that forgot or misreported — which is exactly what both
originating issues describe. It is not tamper-proof against an agent that
decides to route around it. Only a check on already-pushed artifacts is, and
GitHub offers no `pre-receive` hook outside Enterprise. Per-repo CI is the
correct second line of defence and is filed separately.

To keep that cheap, the validator is built as a script with two entry points:
`commit-msg <msgfile>` for the hook, and `--range BASE..HEAD` for CI over a pull
request's commits. Same code, same spec, no second implementation.

## Testing

Vitest covers spec parsing, trigger detection, key-sequence comparison, and
message formatting. Bash suites under `test/` cover install ordering, postStart
behavior, and end-to-end commits, matching the convention in
`local-features/agent-skills/test/`. `.github/workflows/tests.yml` runs
typecheck, lint, vitest, and the existing `local-features/*/test/*.sh` suites,
which have never run in CI.

Fixtures are drawn from real artifacts.

| Fixture | Expected |
| --- | --- |
| `hube/devcontainer#23`'s fabricated block (no `Skills:`) | reject |
| `hube/devcontainer#23`'s amended block | pass |
| `hube/devcontainer#15`'s Codex block (`Model: gpt-5`, no `Skills:`) | reject |
| the same, with `Skills: none` | pass |
| `worklog-contribute`'s current message | reject |
| blank line splitting the block | reject |
| prose line inside the block | reject |
| `Co-Authored-By` not last | reject |
| no trailers at all | pass, silently |
| human-to-human `Co-Authored-By` | pass |
| spec missing | reject, naming the path |
| spec path is a directory | reject, naming the path |
| spec malformed | reject, naming the line |
| commit made as `root` | resolves the same spec; gate applies |
| `mode warn` with a violation | exit 0, diagnosis printed |
| repository `.git/hooks/commit-msg` present | runs; its non-zero status propagates |
| `GIT_CONFIG_NOSYSTEM=1` | gate absent |

The fabricated-block fixture rejects only because `Skills:` became mandatory.
Under the previous contract it was shape-valid, which is the finding that forced
the change.

Assertions match strings only this code can emit (`git-commit-attribution: …`),
never bare `fatal:`, which the underlying tool writes to stderr on its own. Each
assertion is confirmed to **fail** against the code without the fix.

## Verified Behavior

These were established by experiment in the container, not assumed.

- `git interpret-trailers --parse` returns only the trailers after a blank line
  that splits a block, and returns nothing when a non-trailer line sits inside
  it. Contiguity checking is therefore free, and both cases fail closed.
- A message with a prose line above an otherwise valid block parses to zero
  trailers, which is why the trigger reads raw text.
- A global `core.hooksPath` shadows `.git/hooks/commit-msg` completely.
- A repository-local `core.hooksPath` overrides the global one, silently.
- `git commit --no-verify` bypasses the `commit-msg` hook.
- `/etc/gitconfig` is absent in the image; `~/.gitconfig` is provided by
  `hube/devcontainer-dotfiles` at container-create time.
- `node` is nvm-managed, absent from the default `PATH`, and reaches the image as
  a transitive dependency of `ccstatusline`. `/usr/local/share/nvm/current` is a
  version-independent symlink. Node startup is 17–19 ms.
- `~/.claude/CLAUDE.md` is bind-mounted to `~/.codex/AGENTS.md` by
  `local-features/codex`, so one host file already serves both harnesses.
- `local-features/agent-skills`' postStart script runs `git fetch` and never
  checks out, so its clone is a developer working tree and cannot carry
  distributed artifacts.

## Open Questions

- Codex's `AGENTS.md` may not support an inline-import syntax the way Claude
  Code's `CLAUDE.md` supports `@path`. If it does not, the spec pointer in the
  prose is one an agent must choose to follow, which is a further reason the
  rejection message carries the real weight. Unverified.
- Whether `GIT_CONFIG_NOSYSTEM=1` appears in any tooling used in this container.
  The test suite asserts the bypass exists so that it is a known fact rather
  than a surprise.

## Related

- `hube/devcontainer#23` — the enforcement issue this design implements.
- `hube/agent-skills#9` — the producer fix this design depends on.
- `hube/devcontainer#32` and `hube/devcontainer#15` — git SSH signing extraction,
  which inherits the git config placement rule above.
