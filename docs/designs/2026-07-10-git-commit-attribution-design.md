# Git Commit Attribution Design

Status: Accepted — merged via hube/devcontainer#38 (2026-07-18). Implementation:
docs/implementation-plans/2026-08-03-git-commit-attribution-gate-implementation-plan.md
and docs/implementation-plans/2026-08-03-git-commit-attribution-spec-implementation-plan.md.
See the *Changelog* at the end for what has changed across revisions.

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

`git commit` is the one step Claude Code, Codex, and every human in this
container pass through today. The two harnesses share no runtime, no
configuration format, and no environment variables — but both drive git's
porcelain, and a commit message is a harness-neutral artifact. A `commit-msg`
hook therefore generalizes to any agent that commits the way these do,
including agents nobody has configured yet.

That guarantee is scoped to hook-aware porcelain. Plumbing (`git commit-tree`),
libgit2- or JGit-based tools, and commits created through GitHub's web UI or
API never run local hooks. No such producer commits inside this container
today; if one appears, the deferred per-repo CI check (see *Bypasses*) is the
boundary that catches it, not this hook.

One wrinkle arrived with `main`'s Codex inner sandbox: a `git commit` Codex
launches as a sandboxed command runs inside that sandbox, and the gate fires
only if the sandbox exposes system git config, the hooks directory, and the
spec. Commits from an interactive shell are outside the inner sandbox and
unaffected. This is the one unconfirmed link in the premise; see *Reconciliation
with `main`* and *Open Questions*.

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
version      1
mode         warn

trailer      Harness           required
trailer      Harness-Version   required
trailer      Model             required
trailer      Skills            required
trailer      Co-Authored-By    required last

agent-author noreply@anthropic.com
agent-author noreply@openai.com
```

One record per line, so the validator needs no parser and no dependency.
`trailer` records say what must be present; `agent-author` records say when to
enforce at all. The `agent-author` list is the harness-neutral trigger, and
extending it for a new provider is a host-side edit rather than an image
rebuild.

`mode` governs whether a violation is an error or a warning. It lives here, on
the fast channel, so promotion and rollback are a `git pull` apart.

`version` guards the skew this split creates: the spec is live on the next
`git pull`, while the validator rides the image. A validator that does not
recognize the declared version rejects — fail closed, consistent with a missing
spec — naming the remedy: rebuild the container, or pin the spec to the older
grammar. A grammar change therefore ships in two steps: land a validator that
accepts both versions, then flip the spec. Unknown record types within a
supported version also reject rather than being skipped; a typo'd record must
not silently weaken a control.

Why this repo: dotfiles in `hube/devcontainer-dotfiles` are **copied** into
`$HOME` at container create, so changing one requires a restart. `claude-home`
is bind-mounted, so an edit is live in every running container on the next
commit. The file name is harness-neutral; only the Claude-branded directory
containing it appears in this design, confined to one `source:` line — and
that line lives in the consuming `.devcontainer/devcontainer.json`, not in the
Feature. Feature options cannot interpolate into mount declarations, so a
Feature-owned mount would hardcode the Claude path into otherwise
harness-neutral Feature source; instead the Feature owns only the stable
container target path, documents the mount the consumer must declare, and the
postStart warning names it when it is missing. A container built without
Claude — a Codex-only consumer keeping its contract elsewhere — writes its own
one-line mount; the Feature ships unchanged.

### The mechanism — `hube/devcontainer`

A new local Feature, `git-commit-attribution`, harness-neutral and depending on
neither the `claude` nor the `codex` Feature.

```
.devcontainer/devcontainer.json                  (Feature stanza + spec mount)
.devcontainer/local-features/git-commit-attribution/
    devcontainer-feature.json    dependsOn node:2; documents the spec mount
                                 the consumer must declare
    install.sh                   install symlinks, dispatcher, and bundle
                                 verbatim; symlink node; write /etc/gitconfig
    dispatch.sh                  static POSIX sh hook dispatcher (see Hook
                                 Dispatch); no per-container substitution
    dist/validate                committed validator bundle, copied byte for
                                 byte — spec path is a compiled-in default
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

Three moving parts are in play — this gate, the producer fix (`#9`), and the
fallback-safety refactor in `hube/agent-skills`'
[`docs/designs/2026-07-16-worklog-fallback-safety-diagnostics-design.md`](https://github.com/hube/agent-skills/blob/main/docs/designs/2026-07-16-worklog-fallback-safety-diagnostics-design.md).
Only one of the dependencies among them is hard, so it is worth being exact:

- **The gate (this design) depends on neither of the others.** It ships in
  `mode warn`, where it observes and warns but rejects nothing, so it lands
  while `worklog-contribute` still emits its current message. Nothing in
  `agent-skills` blocks it.
- **The producer fix (`#9`) should follow the fallback-safety refactor —
  for rework and collision avoidance, not correctness.** That refactor retypes
  the worklog Git/GitHub helpers from `boolean` to `OperationResult<T>`, and
  both it and `#9` edit `src/worklog/git.ts`. `#9` would *function* if it landed
  first, but it would add a Boolean-returning path the refactor then has to
  retype, and the two would conflict in that file. Landing the refactor first
  avoids both.
- **The `enforce` flip depends on `#9`.** The moment the gate rejects, the
  current hardcoded `worklog-contribute` message fails, so `enforce` must wait
  for `#9`. This is the one hard ordering constraint, and satisfying it is why
  the rollout is warn-first (see *Rollout*).

So the chain is refactor → `#9` → `enforce`; the gate landing in warn mode sits
outside it. This design does **not** implement the `OperationResult` boundary
and does not depend on it — it only constrains the `--trailer` work to be
forwards-compatible with it:

- The `--trailer` flag is passed *through* to `git commit`; a commit that fails
  because the gate rejected it must surface as a typed `COMMIT_FAILED`
  `OperationResult` carrying git's stderr — not as a swallowed `false`. The
  gate's rejection text (`git-commit-attribution: …`) is exactly the kind of
  command evidence that boundary is built to preserve, so the two reinforce
  each other rather than conflict.
- Trailer *assembly* moves out of `src/worklog/git.ts` and into the caller
  (`SKILL.md` composes the flags), which is the same direction the diagnostics
  design pushes: `git.ts` shrinks toward a typed command wrapper that neither
  formats messages nor decides policy.

The foundation this lays: once `--trailer` exists and the contract lives in the
spec, a future `Subagents:` trailer (see *Capturing subagent detail*) is a
caller-side composition change with no producer code at all.

## Container Filesystem

| Path | Provenance | Owner / mode |
| --- | --- | --- |
| `/usr/local/share/git-commit-attribution/hooks/dispatch` + one symlink per githooks(5) hook name | image layer | `root:root` 0755 |
| `/usr/local/share/git-commit-attribution/validate` (bundle, copied verbatim) | image layer | `root:root` 0755 |
| `/usr/local/bin/node` → `/usr/local/share/nvm/current/bin/node` | image layer | `root:root` symlink |
| `/etc/gitconfig` (`core.hooksPath`) | image layer | `root:root` 0644 |
| `/etc/devcontainer/feature/git-commit-attribution/trailer-contract` | read-only bind mount of `${localEnv:HOME}/.claude/git-commit-attribution.conf`, declared in `devcontainer.json` | host file |
| `~/bin/devcontainer-feature/git-commit-attribution/postStartScript.sh` | image layer | container user |

The spec is the only piece on the fast channel. Everything else is code, changes
rarely, and rides the image.

The spec is mounted read-only. `local-features/ssh` establishes the
`"type": "bind,readonly"` idiom for `known_hosts` — though there the Feature
declares its own mount, while here the consumer does, for the portability
reason given under *The spec*. Read-only matters here because
editing the contract you are about to be judged against would be the easiest
bypass available, and the only one that leaves no trace in the commit.

### Spec Resolution

The contract is mounted at a fixed, system-wide path,
`/etc/devcontainer/feature/git-commit-attribution/trailer-contract`, identical
for every user. `core.hooksPath` lives in system scope, so the gate also runs
for commits made as `root`, whose home directory is not where a user-scoped
spec would be; a system path is the one place `root` and every other user
resolve the same spec, with no `~` to expand and nothing per-user to bake.

The path follows the FHS, not the XDG Base Directory Specification, and the
distinction is deliberate. XDG describes a *per-user* resolution mechanism —
`$XDG_CONFIG_HOME` shadowing a `$XDG_CONFIG_DIRS` system default (`/etc/xdg`),
which an application opts into by honoring that search order. This gate does the
opposite on purpose: one canonical contract that `root` and every user resolve
identically, by absolute path, with no per-user override and nothing here
reading `$XDG_CONFIG_DIRS`. That is a fixed system configuration file, which FHS
places directly under `/etc/<name>`. Putting it at `/etc/xdg/…` would borrow the
XDG location while implementing none of the XDG mechanism it signals. `/etc` also
keeps it beside the `/etc/gitconfig` this Feature already writes.

The validator compiles that path in as its default. The dispatcher therefore
invokes `validate commit-msg <msgfile>` with no path argument, `install.sh`
substitutes nothing into the dispatcher, and `dispatch.sh` is a static script.

`--spec PATH` overrides the default and exists for the one caller with no bind
mount: CI, which runs the committed bundle against a checkout and must aim it at
the contract revision it pinned. The hook never passes it. Because the default
is a source constant — the same bytes in the committed `dist/validate` and in a
clean rebuild — the bundle is still copied verbatim (see *The mechanism*), which
the build-diff check proves (see *Testing*). The interpreter is reached the same
way: the committed bundle's shebang is a fixed `#!/usr/local/bin/node`, and
`install.sh` guarantees that symlink exists (see *Node*).

Diagnostics print the fixed system path, never `~` — a message printed during a
root commit names the same `/etc` path as one printed for any other user.

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

Because this rule outlives this Feature, its general form is published for all
future Feature authors in
[`docs/feature-authoring.md`](../feature-authoring.md); the version here is the
worked instance for `core.hooksPath`.

## Hook Dispatch

The dispatcher exists because the enforcement mechanism — a container-wide
`core.hooksPath` — shadows every repository's own hooks. That shadowing is not
incidental to this design; it is a property of the only git mechanism that
reaches *already-existing* repositories without cooperation. The alternatives
that avoid a dispatcher all fail the same test, so they are recorded here rather
than left for a reviewer to re-derive.

### Alternatives to shadowing

- **Install a `commit-msg` hook into each repository's `.git/hooks`.** No
  shadowing, no dispatcher — but it reaches only repositories that exist at
  install time and were enumerated then. The working repositories here are
  bind-mounted under `/workspaces` and are cloned, created, and destroyed
  continuously during a session; a repo cloned five minutes after container
  start would have no gate. It also can't propagate a contract or validator
  update without re-touching every `.git` again. Rejected: it cannot cover the
  common case (a freshly cloned working tree) at all.
- **`git config --global init.templateDir`.** Git copies a template hooks
  directory into each repo's `.git` at `init`/`clone` time. This is strictly
  worse than the per-repo install: it still misses every already-existing
  bind-mounted repo (the template applies only at creation), it *copies* rather
  than links so a contract update never reaches repos already made, and the
  copied `commit-msg` would collide with — overwrite or be overwritten by — a
  repository that ships its own. Rejected for the same coverage gap plus a
  staleness problem.
- **A `git` wrapper earlier on `PATH` that intercepts `commit`.** Fragile
  against callers that invoke git by absolute path or through libgit2/JGit, and
  it would have to re-implement argument parsing to find the message. It moves
  the enforcement off git's own extension point and onto a shadow of the git
  binary. Rejected as less robust than the mechanism git already provides for
  exactly this.
- **`core.hooksPath` with a bare `commit-msg` and no dispatcher.** This is the
  shadowing problem itself, not an escape from it: a hooks directory holding one
  file disables every repository's `pre-commit`, `pre-push`, and the rest,
  silently. The dispatcher is precisely what buys back that behavior.

`core.hooksPath` is therefore chosen *because* it is the one mechanism that
governs repositories the container never enumerated, and the dispatcher is the
price of making it safe. The rest of this section is that dispatcher.

`core.hooksPath` does not add a hook; it **replaces the hook directory, for
every hook git knows**. With it set, a repository's `.git/hooks/pre-commit`
simply never runs — verified, not inferred from the docs. A hooks directory
containing only a `commit-msg` would therefore silently disable every existing
repo hook of every kind under `/workspaces`.

So the installed hooks directory is a dispatcher, not a single hook.
`install.sh` creates one symlink per hook name in githooks(5), all pointing at
one POSIX `sh` script, which:

- resolves the repository's default hook by testing the command before
  composing the path —
  `if common_dir="$(git rev-parse --git-common-dir 2>/dev/null)"; then repo_hook="$common_dir/hooks/$(basename "$0")"; else repo_hook=""; fi`.
  Outside a repository (e.g. `reference-transaction` firing mid-`git init`,
  before the repository is recognized) `rev-parse` fails; `2>/dev/null` keeps
  that transient failure off the user's stderr, and the `if` is what leaves
  the resolved hook path empty, so both the `-x` and `-f` tests below see it
  as absent. Interpolating the command substitution straight into the string
  would instead yield `/hooks/<hook name>` there — a bogus path, not an empty
  one,
- `exec`s it when executable, preserving arguments, stdin, and exit status, and
- warns — the equivalent of git's own `advice.ignoredHook` hint — when the
  repository hook exists but is not executable, then continues as if it were
  absent, so installing the gate does not hide a repository misconfiguration
  git would have surfaced.

For `commit-msg` — and only `commit-msg` — the dispatcher runs the
repository's own `commit-msg` hook **first**, then the validator bundle judges
whatever message file that hook leaves behind. Git permits a `commit-msg` hook
to rewrite the message file in place, so validating first would let a repo
hook silently strip or reorder the required trailers after the only
validation pass; running the repo hook first means the validator always
judges the message git will actually use. The repo hook's own non-zero exit
stops the commit before the validator ever runs. Control returns to the
dispatcher after the repo hook (rather than `exec`ing it) because validation
still has to run afterward; every other hook name keeps the plain `exec`
chain described above.

### Presence-Sensitive Hooks

Exiting 0 when no repository hook exists is only correct for hooks whose no-op
equals absence — vetoes and notifications, which is most of githooks(5). Two
hooks change git's behavior by merely existing, and each gets an adapter in the
dispatcher.

**Absence-equivalent means ref, worktree, and index outcomes are identical to
having no hook installed.** It does not mean identical diagnostics: git
attributes a refusal to the hook that made it, so the operator sees
`push-to-checkout hook declined` where an uninstalled gate would have said
`Working directory has unstaged changes`. The push is refused either way and
the repository is left in the same state. Equivalence is claimed for what the
control protects — refs and working trees — and nowhere else.

- **`push-to-checkout`**: under `receive.denyCurrentBranch=updateInstead`, an
  exit-0 hook tells git the worktree update was handled. A bare `exit 0` lets
  the ref advance while the worktree and index stay at the old commit, leaving
  the repository dirty. When no repository hook exists, the dispatcher emulates
  git's built-in default — refuse when the worktree or index differ from
  `HEAD`, otherwise update both:

  ```sh
  git update-index -q --ignore-submodules --refresh &&
  git diff-files --quiet --ignore-submodules -- &&
  git diff-index --quiet --cached --ignore-submodules HEAD -- &&
  git read-tree -u -m HEAD "$1"
  ```

  The `--` on `diff-index` is load-bearing and is the reason the chain is given
  verbatim. The hook's cwd is `$GIT_DIR`, which contains a file named `HEAD`,
  so `diff-index`, whose argument grammar is `<tree-ish> [--] [<path>…]`, reads
  a bare `HEAD` as ambiguous and aborts the adapter. `read-tree` takes only
  tree-ish arguments and parses no pathspec, so it needs no `--` — adding one
  is harmless but does not address the ambiguity, which arises before
  `read-tree` runs.

- **`proc-receive`**: replaces receive-pack's internal command execution for
  refs matching `receive.procReceiveRefs`, speaking a pkt-line protocol no
  generic script can emulate. A repository hook, when present, gets the
  protocol passed through untouched by `exec`. When none exists the dispatcher
  exits non-zero, which rejects the matched ref exactly as an absent hook does.
  Equivalence here is ref-level only, and narrower than it looks: it is
  established for the single-ref rejection path, not for multi-ref or atomic
  pushes, and the two paths report different remote errors. That is sufficient,
  because both outcomes are *reject the push*; a dispatcher that instead exited
  0 would tell receive-pack the refs were handled when nothing had handled
  them. Nothing in this container sets `receive.procReceiveRefs`; the adapter
  exists so nothing breaks if something ever does.

Every other githooks(5) hook is delegation-safe: the `pre-*` and `*-msg`
families veto, the `post-*` family and `reference-transaction` observe, and
`fsmonitor-watchman` runs only where `core.fsmonitor` explicitly names it. A
hook name added by a future git version must be classified
absence-equivalent-or-adapter before it joins the symlink list.

Two resolution details are load-bearing, both established by experiment:

- `git rev-parse --git-path hooks` honors `core.hooksPath`, so it returns the
  gate's own directory — a dispatcher built on it would exec itself forever.
  The common-dir form ignores `core.hooksPath` and is the recursion guard.
- In a linked worktree, `.git` is a file, so the naive `.git/hooks/<name>`
  resolves nowhere. `--git-common-dir` returns the main repository's `.git`,
  where hooks actually live. Claude and Codex agents in this container work in
  linked worktrees routinely, so this is the common case, not an edge.

Hook names added by future git versions are not dispatched until the symlink
list in `install.sh` is updated — deliberately, given the classification rule
above; the list records its provenance (githooks(5) of the image's git) beside
it.

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
version-independent symlink that survives node upgrades. The committed bundle's
shebang is a fixed `#!/usr/local/bin/node`, so that symlink — not a per-container
rewrite — is what points every commit at a working interpreter. `install.sh`
validates the interpreter is executable and fails the install loudly if not,
rather than deferring the discovery to someone's first commit. Fixing the
shebang at build time, together with the compiled-in default spec path
(see *Spec Resolution*), is what leaves no container-specific value in the
artifact, so the bundle is copied byte for byte.

The bundle is **committed**, built by esbuild into a single dependency-free file
using only `node:fs` and `node:child_process`. The image build never runs
`npm install`. One bundle serves both entry points, dispatching on argv:
`commit-msg <msgfile>` when the dispatcher invokes it (the validator uses its
default spec path), and `--range BASE..HEAD --spec PATH` when CI runs the
committed `dist/validate` directly from a checkout against a pinned contract.

Measured node startup in this image is 17–19 ms, negligible beside SSH signing.

The dispatcher itself is POSIX `sh`, so hooks other than `commit-msg` never pay
the node dependency. If the interpreter is missing despite all of this, the
dispatcher cannot run the validator, and it treats a validator it cannot
execute as a rejection — fail closed, naming what it could not run.

### Language split

All contract logic — spec parsing, trigger generation, trailer-sequence
comparison, diagnostics — is TypeScript, in `src/git-commit-attribution/` and
tested with Vitest. The rule is: everything with a decision in it is TypeScript;
the remaining shell is thin plumbing with no branching a test would want to
assert on. Two shell shims survive that rule, each for a reason that is not
stylistic:

- **`install.sh` is the node bootstrap.** It creates the `/usr/local/bin/node`
  symlink the TypeScript depends on and validates the interpreter. It cannot
  itself be TypeScript without depending on the very thing it installs, so it
  stays the image-build shell every other Feature here uses (`node:2` is a
  build-time `dependsOn`, and `install.sh` runs before that guarantee is
  observable at a fixed path).
- **`dispatch.sh` runs for *every* git hook, not just `commit-msg`.** Making it
  node would put node startup on the path of `pre-commit`, `post-commit`,
  `pre-push`, and the rest, and — worse — would extend "fail closed if node is
  missing" from one hook to all of them, so a broken interpreter would block
  operations that never needed node. It is deliberately POSIX `sh`: symlink
  resolution, a recursion guard, and an `exec`. Its only node-dependent branch
  is the `commit-msg` case, which shells out to the TypeScript bundle rather
  than reimplementing anything.

`postStartScript.sh` could be TypeScript, since node is live by postStart, but
it is kept shell to match the established non-blocking postStart idiom
(see *Failure Behavior*); its logic is a mount check and a `core.hooksPath`
scan, neither of which carries contract decisions. The net effect is that the
shell holds no rule the contract depends on — only a bootstrap, a router, and a
warning.

This split — logic in TypeScript, thin shell shims justified by a
bootstrap-or-hot-path reason — is generalized for future Feature authors in
[`docs/feature-authoring.md`](../feature-authoring.md).

## Validation Flow

```
dispatch.sh commit-msg <msgfile>
  │
  ├─ repository's own commit-msg hook, if executable, runs FIRST
  │    non-zero exit → stop; the validator never runs, commit is not created
  │    (may rewrite <msgfile> in place; the validator judges what it leaves)
  │
  validate commit-msg <msgfile>          (dispatcher passes no --spec)
  │
  ├─ read spec  ← the compiled-in default path, or --spec if CI overrides it
  │             (see Spec Resolution)
  │    missing, malformed, or unsupported version
  │      → REJECT, naming the path and the offending line
  │
  ├─ trigger?  raw text match on ^<Key>: for each trailer key in the spec
  │            except Co-Authored-By, or
  │            ^Co-Authored-By: <address listed as agent-author>
  │    no → PASS, silently
  │
  ├─ validate: git interpret-trailers --parse <msgfile> → ordered key list
  │    compare against the spec's required sequence
  │      violation, mode enforce → REJECT
  │      violation, mode warn    → print diagnosis, note it will become
  │                                an error, PASS
  │      no violation            → PASS
  │
  └─ PASS → the commit proceeds (the repository's own commit-msg already ran, above)
     REJECT → non-zero exit; the commit is not created
```

Two reads of the message, for two different questions.

The **trigger** asks whether the commit claims to be agent-authored, and must
read raw text. A message with a stray prose line above the block parses to zero
trailers, so a trigger based on parsed output would see nothing, decline to
fire, and pass the non-compliant commit. The malformed message would evade the
check precisely because it is malformed.

Trigger patterns are generated from the spec's `trailer` records, not
hardcoded, so detection cannot drift from the contract it enforces: a key added
to the spec is a key that trips the trigger, with no second list to update.
`Co-Authored-By` is the exception — it appears in human-to-human commits, so it
triggers only with an address on the `agent-author` list.

The **validator** asks whether the claim is well-formed, and delegates entirely
to `git interpret-trailers --parse`. Git's definition of a trailer block is
therefore the contract's definition, and the hook can never disagree with the
`git log -1 --pretty=%B | git interpret-trailers --parse` check the contract
already prescribes. Two properties come free: a blank line inside the block
makes git return only the trailers after it, and a stray line makes git return
nothing. Both surface as missing required trailers.

Commits that trip no trigger pass silently: human-authored commits, GitHub merge
commits, and human-to-human `Co-Authored-By` among them. The repository's own
`commit-msg` hook already ran before any of this, unconditionally (see *Hook
Dispatch*); a PASS here means the commit git already handed to that hook is
also allowed to proceed.

### Sequence Semantics

"Compare against the spec's required sequence" means, precisely:

- The required keys must appear in the parsed trailer list in spec order, as a
  contiguous run — nothing sits between `Harness` and the final
  `Co-Authored-By` that is not itself a required trailer.
- Each required key other than `Co-Authored-By` must appear **exactly once in
  the entire trailer list**, not merely once inside a valid run. Without this,
  a message carrying two attribution blocks — one valid, one conflicting —
  would pass on the strength of the valid one.
- `Co-Authored-By` may repeat. A commit with several contributors — a human
  pair, a second harness — carries several `Co-Authored-By` trailers, and
  `required last` means the run of them ends the block.
- Trailers the spec does not mention (`Signed-off-by`, Gerrit `Change-Id`) are
  permitted **before** the block. The contract says the message *ends* with the
  attribution block; it does not claim to be the only trailer convention in
  existence.
- `git commit --signoff` appends `Signed-off-by` after everything else, so it
  lands after `Co-Authored-By` and rejects. Sign-offs belong above the block.
  No repository this gate governs uses DCO sign-offs today; if one appears,
  that is a spec-grammar change, not a hook edit.

The block attributes the harness that **created the commit** — the
orchestrating agent, when subagents are involved. Other contributors, human or
AI, appear as additional `Co-Authored-By` trailers, never as a second
`Harness:`/`Model:` block.

### Capturing subagent detail

A single orchestrator block plus `Co-Authored-By` lines records *who
contributed* but flattens *how* — a subagent's model and the skill it ran are
not distinguishable from a human co-author. Whether to capture more is a
contract decision, not a hook one, so the design fixes the grammar to keep the
richer options open rather than choosing among them now. The alternatives
considered:

- **One `Co-Authored-By` per subagent (current).** Truthful about contributors,
  parseable by every tool that already reads `Co-Authored-By`, and it composes
  with human pairs. It loses the skill each subagent ran and does not mark which
  co-authors were AI. This is the baseline the grammar already enforces.
- **A second `Harness:`/`Model:` block per subagent.** Rejected: it breaks the
  single-block invariant the whole validator rests on — "the message *ends* with
  one attribution block, `Co-Authored-By` last" — and makes "which harness
  created the commit" ambiguous, which is the one fact the block exists to state.
- **An optional `Subagents:` trailer** listing `model (skill)` entries,
  analogous to `Skills:`. This is the forwards-compatible path: it is one more
  `trailer` record the spec can add later with `required` or optional
  cardinality, the trigger picks it up automatically (patterns are generated
  from the spec — see *Validation Flow*), and it sits inside the existing block
  without a second `Harness:`. The design does **not** add it now — no consumer
  needs the field yet, and adding an unused required trailer is the same YAGNI
  the `Skills: none` sentinel was careful to avoid — but the grammar and the
  spec format are chosen so it costs one spec line when a consumer does.
- **Free-form subagent notes in the commit body.** Always available, never
  machine-checkable. Fine for a human reader, useless as a control. Left as the
  escape hatch it already is, not a structured mechanism.

The settled position: keep orchestrator attribution plus `Co-Authored-By`, and
reserve `Subagents:` as the extension point. This aligns with the producer
work's typed-trailer direction (see *The producer*): a repeatable
`--trailer "Subagents: …"` needs no new code, only a spec that lists the key.

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

Spec: /etc/devcontainer/feature/git-commit-attribution/trailer-contract
```

The spec path shown is the validator's compiled-in default — the same fixed
system path for every user, for the reason given under *Spec Resolution*.

The postStart script never blocks container start, matching the idiom
`local-features/agent-skills/bin/.../postStartScript.sh` establishes and now
published for all Feature authors in
[`docs/feature-authoring.md`](../feature-authoring.md). It warns when the spec
mount is absent, and it names any repository under `/workspaces` whose local
`core.hooksPath` shadows the gate.

## Rollout

The gate ships in `mode warn` and is promoted to `mode enforce` by editing the
spec on the host. No rebuild, reversible in seconds. The sequence is tracked in
[`hube/devcontainer#51`](https://github.com/hube/devcontainer/issues/51).

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
`commit-msg <msgfile>` for the hook, and `--range BASE..HEAD --spec PATH` for CI
over a pull request's commits. Same code, same spec grammar, no second
implementation. The hook uses the compiled-in default spec path; CI has no bind
mount, so it must supply `--spec` pointing at the contract revision it pinned.
How a per-repo workflow obtains and pins that revision is a decision for that
deferred design; this repo's own `tests.yml` exercises range mode against
fixture specs committed under `test/`.

## Testing

Vitest covers spec parsing, trigger detection, key-sequence comparison, and
message formatting. Bash suites under `test/` cover install ordering, postStart
behavior, and end-to-end commits, matching the convention in
`local-features/agent-skills/test/`. `.github/workflows/tests.yml` runs
typecheck, lint, vitest, a build-diff check
(`npm run build && git diff --exit-code -- dist/`) so a stale committed bundle
fails CI, and the existing `local-features/*/test/*.sh` suites, which have never
run in CI. The build-diff check is what makes the byte-identical-bundle claim
enforceable rather than aspirational: a bundle carrying a container-specific
path or shebang could not match a clean rebuild.

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
| repeated `Co-Authored-By` ending the block | pass |
| duplicate `Model:` elsewhere in the trailer list | reject |
| two complete attribution blocks, one valid | reject |
| `Signed-off-by` before the block | pass |
| `--signoff` (appends `Signed-off-by` after the block) | reject |
| spec missing | reject, naming the path |
| spec path is a directory | reject, naming the path |
| spec malformed | reject, naming the line |
| spec with an unsupported `version` | reject, naming the remedy |
| commit made as `root` | resolves the same fixed system-path spec; gate applies |
| committed `dist/validate` vs. a clean rebuild | byte-identical; build-diff check passes |
| hook invocation (no `--spec`) | validator uses its compiled-in default spec path |
| CI `--range` with `--spec` | validates the pinned contract; default overridden |
| `mode warn` with a violation | exit 0, diagnosis printed |
| repository `.git/hooks/commit-msg` present | runs; its non-zero status propagates |
| repo `commit-msg` present, message trips no trigger | repo hook still runs |
| repo `commit-msg` present, `mode warn` violation | repo hook still runs |
| repository `.git/hooks/pre-commit` present | still runs with the gate installed |
| repository hook present but not executable | warning printed; treated as absent |
| commit from a linked worktree | default hooks resolve via the common dir; gate applies |
| `updateInstead` push, clean worktree, no repo hook | ref advances; worktree and index match the pushed tip; tree clean |
| `updateInstead` push, dirty worktree, no repo hook | refused; ref unmoved; local edit preserved |
| `updateInstead` push, repo `push-to-checkout` present | repo hook runs |
| push to a `receive.procReceiveRefs` ref, no repo hook | ref rejected, as with the gate absent |
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
- A global `core.hooksPath` replaces the hook directory for **every** hook:
  with it set, a repository's `.git/hooks/pre-commit` no longer runs.
- `git rev-parse --git-path hooks` honors `core.hooksPath` and returns the
  gate's own directory; `--git-common-dir` ignores it, and from a linked
  worktree — where `.git` is a file — resolves the main repository's `.git`,
  where hooks actually live.
- A repository-local `core.hooksPath` overrides the global one, silently.
- A present-but-no-op `push-to-checkout` under
  `receive.denyCurrentBranch=updateInstead` lets the ref advance while the
  worktree and index stay at the old commit, leaving the repository dirty —
  presence alone overrides git's built-in update.
- The emulation chain given under *Presence-Sensitive Hooks* reproduces git's
  built-in `updateInstead` behavior: the clean case advances the ref and
  updates the worktree and index, and the dirty case refuses and preserves the
  local edit, each matching a control push made with no hook installed.
- The hook's cwd is `$GIT_DIR`. `git diff-index … HEAD` there is ambiguous
  against the `HEAD` file and aborts the chain; `--` after `HEAD` resolves it.
  `git read-tree -u -m HEAD "$1"` is unaffected, parsing no pathspec — the only
  load-bearing `--` in the chain is the one on `diff-index` (`diff-files` takes
  no tree-ish, so its `--` is cosmetic), and with it in place the chain completes
  and updates the worktree.
- A push to a `receive.procReceiveRefs`-matched ref is rejected whether the
  hook is missing or present-and-failing, so a fail-fast adapter preserves the
  ref outcome. The remote's error text differs between the two
  (`cannot find hook 'proc-receive'` versus
  `fail to negotiate version with proc-receive hook`), so the equivalence is
  ref-level, not diagnostic.
- `git commit --no-verify` bypasses the `commit-msg` hook.
- `/etc/gitconfig` is absent in the image; `~/.gitconfig` is provided by
  `hube/devcontainer-dotfiles` at container-create time.
- `node` is nvm-managed, absent from the default `PATH`, and reaches the image as
  a transitive dependency of `ccstatusline`. `/usr/local/share/nvm/current` is a
  version-independent symlink. Node startup is 17–19 ms.
- `~/.claude/CLAUDE.md` is bind-mounted to `~/.codex/AGENTS.md` by
  `local-features/codex`, so one host file already serves both harnesses. Still
  true at the tip of `main` (`devcontainer-feature.json` mounts
  `${localEnv:HOME}/.claude/CLAUDE.md` → `~/.codex/AGENTS.md`).
- Codex (`codex-cli 0.144.5`, installed in this image) loads `AGENTS.md` as a
  whole **project doc** subject to a truncation budget, with no `@path`
  inline-import expansion: its `agents_md` loader reads the file wholesale, and
  `~/.codex/config.toml` sets `project_doc_fallback_filenames = ["CLAUDE.md"]`.
  Claude Code, by contrast, expands `@path` in `CLAUDE.md` to the imported
  file's content. Because the **same** host bytes are read as `CLAUDE.md` by one
  harness and `AGENTS.md` by the other, a `@path` line would silently no-op
  under Codex. So the spec pointer in the shared prose must be plain text a
  reader chooses to follow — which is a further reason the rejection message,
  not the prose pointer, carries the teaching weight. This resolves a prior open
  question.
- `GIT_CONFIG_NOSYSTEM=1` is **live** in this container's tooling: the
  `security-guidance` Claude Code plugin hook sets it (together with
  `GIT_CONFIG_GLOBAL=/dev/null`) for a read-only, non-committing agentic
  security-review subprocess that runs `git diff/log/show`. That subprocess
  never commits, so it does not bypass the gate today — but the env is present
  and would disable the gate for any future committing process that inherited
  it, so the *Bypasses* entry is a real mechanism, not a hypothetical. This
  resolves a prior open question.
- `local-features/agent-skills`' postStart script runs `git fetch` and never
  checks out, so its clone is a developer working tree and cannot carry
  distributed artifacts.

## Reconciliation with `main`

Reviewed against the tip of `main` after the Codex unconfined-runtime work
merged (`hube/devcontainer#46`, #47, #48). What changed and what it means here:

- **No CI workflow was added.** `main` still ships only
  `.github/workflows/publish.yaml`; `local-features/*/test/*.sh` have still never
  run in CI. The proposed `tests.yml` remains the first test workflow, unchanged.
- **The Codex Feature now builds an inner bwrap sandbox** for the commands Codex
  launches, on a container-wide relaxed outer Docker boundary. This touches the
  enforcement premise: a `git commit` Codex runs as one of those sandboxed
  commands executes inside that inner sandbox, so the gate fires only if the
  sandbox exposes `/etc/gitconfig`, the hooks directory, and the read-only spec
  mount to it. Codex's own `NOTES.md` records that interactive shells and
  lifecycle scripts do **not** get the inner sandbox, so a commit made from a
  shell is unaffected; the sandboxed-command path is the one to confirm. See
  *Open Questions*.
- **Nothing in `main` moved git config, hooks, or the `claude-home` mount**, so
  the git-config placement rule and the `core.hooksPath` mechanism are
  unaffected. The `NOTES.md`/`MAINTAINERS.md` split the Codex Feature now models
  is the documentation convention this Feature already follows.

## Open Questions

- Whether a `git commit` Codex launches **inside its inner bwrap sandbox** sees
  `/etc/gitconfig`, `/usr/local/share/git-commit-attribution/hooks`, and the
  read-only spec mount. Codex's default sandbox exposes the root filesystem
  read-only with a writable workspace, which would keep all three visible and
  the gate active — but this has not been exercised inside an actual rebuilt,
  Codex-enabled container, which is the one unverified link in the "every
  commit passes through the gate" claim. `test/test-codex-sandbox.sh` is the
  committed probe that answers it: it runs a violating fixture through
  `codex sandbox -P :workspace -C <dir> git commit` and checks for the exact
  warn-mode diagnosis on stderr plus a created commit. This is resolved by
  running that script inside the first rebuilt container.

## Related

- `hube/devcontainer#23` — the enforcement issue this design implements.
- `hube/devcontainer#51` — the warn-then-enforce rollout tracker.
- `hube/agent-skills#9` — the producer fix this design depends on.
- `hube/agent-skills` `docs/designs/2026-07-16-worklog-fallback-safety-diagnostics-design.md`
  — the fallback-safety refactor the producer fix should follow (see *The
  producer*).
- `hube/devcontainer#32` and `hube/devcontainer#15` — git SSH signing extraction,
  which inherits the git config placement rule, now generalized in
  `docs/feature-authoring.md`.
- `docs/feature-authoring.md` — general Feature-authoring conventions extracted
  from this design.

## Changelog

Substantive design changes, newest first. The body above describes the current
settled design; the entries below list what changed between revisions. This
section is a deliberate exception to the general guidance against narrating a
document's revision history, kept at the owner's request
([#38 review](https://github.com/hube/devcontainer/pull/38#discussion_r3606547716)).

- **2026-08-04** — Implemented per
  `docs/implementation-plans/2026-08-03-git-commit-attribution-gate-implementation-plan.md`
  and the companion
  `docs/implementation-plans/2026-08-03-git-commit-attribution-spec-implementation-plan.md`:
  the TypeScript validator, hook dispatcher, install/postStart scripts, and CI
  landed in `mode warn`. Added `test/test-codex-sandbox.sh`, the in-container
  probe that resolves the Codex-sandbox open question. `hube/agent-skills#9`
  has since closed, so the `enforce` flip now gates only on the rollout state
  tracked in `#51`.
- **2026-07-17** — Spec resolution reworked to a fixed, system-wide FHS path
  (`/etc/devcontainer/feature/git-commit-attribution/trailer-contract`) that
  serves `root` and every user identically. The validator compiles that path in
  as its default, so the hook passes no `--spec` and the dispatcher is static;
  `--spec` remains a CI-only override. Dependency chain
  (refactor → `#9` → `enforce`) stated explicitly, with the gate landing in warn
  mode outside it. TypeScript-for-logic and non-blocking-postStart conventions
  published in `docs/feature-authoring.md`; rollout tracked in `#51`.
- **2026-07-17** — Reconciled with the tip of `main` after the Codex
  unconfined-runtime work merged. Both prior open questions verified in the
  container: Codex loads `AGENTS.md` wholesale with no `@path` import, and
  `GIT_CONFIG_NOSYSTEM=1` is live in tooling but only on a non-committing path.
  The remaining open question is Codex inner-sandbox visibility of the gate.
- **2026-07-14** — `push-to-checkout` emulation given as a verbatim chain;
  absence-equivalence defined as identical ref/worktree/index outcomes, not
  identical diagnostics, and scoped accordingly for `proc-receive`.
- **2026-07-10** — Hook composition reworked: `core.hooksPath` plus a chaining
  dispatcher across every githooks(5) name, with presence-sensitive adapters for
  `push-to-checkout` and `proc-receive`; spec mount decoupled to the consumer.
  `Skills:` made mandatory with a `none` sentinel.
- **2026-07-10** — Initial design: `commit-msg` gate, `git interpret-trailers`
  as the parser, spec on the `claude-home` fast channel, warn-then-enforce
  rollout.
