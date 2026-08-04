# git-commit-attribution

A local devcontainer Feature that installs a container-wide `commit-msg` gate
enforcing the agent-attribution trailer contract on every git commit made
inside the container.

## Behavior

The gate reads a spec (the trailer contract) and, for every `commit-msg`
invocation, checks the candidate commit message against it. The spec's
`mode` selects the enforcement level:

- `mode: warn` — a violation is diagnosed to stderr but the commit proceeds
  (exit 0).
- `mode: enforce` — a violation rejects the commit (non-zero exit); the
  commit is not created.

The gate **fails closed**: a missing spec, a spec path that is not a regular
file, a malformed spec, an unsupported spec `version`, an unknown record
type, or an unexecutable validator all reject the commit with a
problem → consequence → remedy message, regardless of `mode`. Only an actual
parsed spec in `mode: warn` lets a violating commit through.

## Consumer mount

This Feature owns only the container-side path,
`/etc/devcontainer/feature/git-commit-attribution/trailer-contract`. Feature
options cannot interpolate into mount declarations, so the Feature cannot
declare the bind mount itself — the consuming `devcontainer.json` must. Copy
this block into the consumer's `mounts`:

```jsonc
{
  "type": "bind,readonly",
  "source": "${localEnv:HOME}/.claude/git-commit-attribution.conf",
  "target": "/etc/devcontainer/feature/git-commit-attribution/trailer-contract"
}
```

Keeping the mount on the consumer side also means a Codex-only consumer with
no Claude-branded host directory can supply its own source path; the Feature
ships unchanged either way.

## Bypasses

Four ways the gate does not apply, stated plainly:

- **A repository with its own `core.hooksPath`.** Local git config outranks
  the system-scope `core.hooksPath` this Feature writes, so a repo already
  running husky, lefthook, or pre-commit bypasses the gate silently, by
  accident. Not fixable from global config. The postStart script names any
  such repository under the scan root, along with its `core.hooksPath`
  value.
- **`git commit --no-verify`.** One flag skips the `commit-msg` hook
  entirely. This is also the documented escape hatch for the one commit that
  needs to land while the spec itself is broken.
- **Commits made outside the container.** There is no gate at all outside
  this container's git config.
- **`GIT_CONFIG_NOSYSTEM=1`.** Disables system-scope git config, which is
  where `core.hooksPath` lives, so it disables the gate. This is not
  hypothetical: it is live in this container's tooling today (the
  security-guidance Claude Code plugin hook sets it, together with
  `GIT_CONFIG_GLOBAL=/dev/null`, for a read-only, non-committing security-review
  subprocess). That subprocess never commits, so it does not bypass the gate
  today, but any future committing process that inherited the same
  environment would.

## Hook-name policy

The symlink farm in `install.sh` (`HOOK_NAMES`) is every hook name documented
in githooks(5) for git 2.53 (the image's git), exactly once, no extras. A
name added by a future git version must be classified before joining the
list: **absence-equivalent** (exiting 0 with no repository hook installed
produces the same ref/worktree/index outcome as having no hook at all — true
of most of githooks(5)) or in need of its own **adapter** (the hook changes
git's behavior merely by existing, so a bare passthrough would silently
change behavior).

Two hooks in the current list are presence-sensitive and get adapters rather
than a bare `exit 0`:

- **`push-to-checkout`** — under `receive.denyCurrentBranch=updateInstead`,
  an exit-0 hook tells git the worktree update was already handled. A bare
  passthrough would let the ref advance while the worktree and index stayed
  at the old commit, leaving the repository dirty. The adapter emulates
  git's own built-in `updateInstead` behavior instead: it refuses when the
  worktree or index differ from `HEAD`, and otherwise updates both.
- **`proc-receive`** — speaks a pkt-line protocol no generic script can
  emulate. The adapter fails, which rejects the matched ref exactly as an
  absent hook does; a bare `exit 0` would instead claim refs were handled
  when nothing handled them.

## Failure handling

The gate never blocks container start: `postStartScript.sh` only warns, and
always exits 0, whether the spec is missing, misplaced, or a repository's
local `core.hooksPath` shadows the gate. A missing spec warns at postStart
and rejects at commit time; a malformed spec passes the postStart
file-existence check silently and is caught only at commit time — the
fail-closed behavior described under *Behavior* above. Under an active
container-wide `core.hooksPath`, a
plain `git init` is expected to emit benign `fatal: not a git repository`
stderr noise twice (the `reference-transaction` hook fires before the
repository is fully initialized); the exit status is 0 and the repository is
intact, so this is cosmetic only.
