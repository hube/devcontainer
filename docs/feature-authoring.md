# Authoring local Features

Conventions every local Feature under `.devcontainer/local-features/` is
expected to follow. These are extracted from patterns already load-bearing in
this repo so that a new Feature inherits a rule rather than re-deriving it from
an existing Feature by imitation. Each rule links to the Feature that first
established it.

## Where a Feature writes git config

**The scope a Feature writes a git setting to is determined by what happens when
the setting is *absent*, not by what the setting does.**

- A setting whose absence **degrades gracefully** — the user notices, nothing
  silently misbehaves — goes to **user scope**, written at **postStart**,
  conditional on its prerequisites, warning and skipping when they are unmet.
  That is `~/.config/git/<feature>.inc` with an `include.path` entry in
  `~/.gitconfig`. postStart is required because `install.sh` runs at image build
  and cannot see bind mounts or the running user's home.

- A setting that is a **control** — where silent absence produces a *false
  belief that the control is active* — goes to **system scope**,
  `/etc/gitconfig`, written by `install.sh` while it still holds root, and
  written **unconditionally**. A control that might not be there is not a
  control.

The deciding question is: *can this setting's correctness be checked later, at
the moment of use?* If a missing or wrong value fails loudly at use time, user
scope is fine. If a missing value just means the protection quietly isn't there,
it must be a build-time system-scope write so it cannot be skipped.

Precedence is system < global < local, so a system-scope control does not
disturb a user's deliberate global override, and a `~/.gitconfig` laid down at
container-create time does not shadow it. A repository-local setting still wins,
which is a documented bypass for any control written this way — state it in the
Feature's `NOTES.md`.

*Established by `git-commit-attribution` (`core.hooksPath` as a system-scope
control) and inherited by the git SSH signing extraction
(`hube/devcontainer#32`, #15). See
[the git-commit-attribution design](designs/2026-07-10-git-commit-attribution-design.md).*

## postStart never blocks container start

A Feature's `postStartScript.sh` must **never fail container start**. If a
prerequisite is missing — an absent bind mount, an SSH agent with no identities,
an unreachable remote — the script writes a problem/consequence/remedy message
to stderr and exits 0, leaving the container usable. Diagnosis belongs in the
message, not in a non-zero exit that strands the user with no shell.

State the problem, then its consequence, then the remedy, in that order, and
fold in the underlying command's own output rather than telling the user to
re-run it.

*Established by `agent-skills` and `github-cli-config`; both come up even when
their clone, auth, or setup step fails.*

## Logic goes in TypeScript, not shell

Anything with a decision in it — parsing, validation, comparison, diagnostics —
belongs in TypeScript, built to a committed, dependency-free bundle and tested
with Vitest. Shell is for thin plumbing with no branching a test would want to
assert on: a bootstrap, a router, an `exec`.

A shell shim is justified only by a reason that is not stylistic. Two recur:

- **A bootstrap cannot depend on what it installs.** `install.sh` runs at image
  build and sets up the interpreter (e.g. the `node` symlink), so it cannot
  itself be TypeScript.
- **A hot path shared by unrelated hooks should not take on a heavy runtime.**
  A dispatcher that runs for every git hook stays POSIX `sh` so that a broken
  interpreter, or startup cost, does not reach hooks that never needed it — only
  the one branch that needs the logic shells out to the bundle.

When you reach for shell, name which of these applies; if neither does, the code
has a decision in it and belongs in TypeScript.

*Established by `git-commit-attribution`: the logic is a TypeScript validator,
while `install.sh` (a bootstrap) and the hook dispatcher (a hot path) stay
shell for the two reasons above.*

## Feature-owned vs. consumer-owned mounts

A Dev Container Feature cannot interpolate its options into a mount declaration,
so a Feature that needs a host path mounted has two choices:

- **Feature-declares the mount** when the source path is stable and
  harness-neutral (e.g. `local-features/ssh` mounts `known_hosts`
  `bind,readonly`).
- **Consumer-declares the mount** when the source path is specific to one
  harness or host layout, so hardcoding it would leak that path into otherwise
  neutral Feature source. The Feature then owns only the stable *container
  target* path, documents the mount the consumer must add to
  `devcontainer.json`, and warns at postStart when the mount is absent.

*Established by `local-features/ssh` (Feature-declared) and
`git-commit-attribution` (consumer-declared spec mount).*

## Documentation split: `NOTES.md` and `MAINTAINERS.md`

User-facing runtime requirements, failure handling, and bypasses go in the
Feature's `NOTES.md`. Operational procedures for accepting and publishing
changes — local acceptance, publication, post-publication verification,
cleanup, retirement — go in a `MAINTAINERS.md` beside it.

*Established by `local-features/codex`.*
