# git-commit-attribution

A local devcontainer Feature that installs a container-wide `commit-msg` gate
enforcing the agent-attribution trailer contract on every git commit made
inside the container. One dispatcher is symlinked under every githooks(5)
name; only `commit-msg` validates.

Written for the owner and this repository's maintainers, whose host already
carries `~/.claude`. `Decided (owner, 2026-08-05, in session)`

## Behavior

The gate reads a spec (the trailer contract) and, for every `commit-msg`
invocation, checks the candidate commit message against it. The spec's
`mode` selects the enforcement level:

- `mode: warn` — a violation is diagnosed to stderr but the commit proceeds
  (exit 0).
- `mode: enforce` — a violation rejects the commit (non-zero exit); the
  commit is not created.

The gate **fails closed**: a spec it cannot find, read, or parse rejects the
commit regardless of `mode`, with a problem → consequence → remedy message
naming the specific cause. Only an actual parsed spec in `mode: warn` lets a
violating commit through.

## Consumer mount

This Feature owns only the container-side path,
`/etc/devcontainer/feature/git-commit-attribution/trailer-contract`. Feature
options cannot interpolate into mount declarations, so the Feature cannot
declare the bind mount itself — the consuming `devcontainer.json` must. Copy
this block into that file's top-level `mounts` array:

```jsonc
{
  "type": "bind,readonly",
  "source": "${localEnv:HOME}/.claude/git-commit-attribution.conf",
  "target": "/etc/devcontainer/feature/git-commit-attribution/trailer-contract"
}
```

That source is the contract itself: `hube/claude-home` supplies it at
`~/.claude/git-commit-attribution.conf` on the host, and `mode` is a field in
it — so a host checkout of `hube/claude-home` at `~/.claude` is what both
states the required trailers and sets the enforcement level.

The mount takes effect on a container rebuild. A healthy install then reads
back `git config --system core.hooksPath` as the hooks directory the Feature
wrote there, `/usr/local/share/git-commit-attribution/hooks`, and postStart —
this Feature's `postStartCommand` script, whose output lands in the container
start log — prints nothing. Every postStart message names a problem.

## Bypasses

Four ways the gate does not apply, stated plainly:

- **A repository with its own `core.hooksPath`.** Worktree, local, or global
  git config all outrank the system-scope `core.hooksPath` this Feature
  writes, so a repo already running husky, lefthook, or pre-commit bypasses
  the gate silently, by accident. Not fixable from global config. postStart
  warns when it finds one, naming the repository and the path it sets.
- **`git commit --no-verify`.** One flag skips the `commit-msg` hook
  entirely. This is also the documented escape hatch for the one commit that
  needs to land while the spec itself is broken.
- **Commits made outside the container.** There is no gate at all outside
  this container's git config.
- **`GIT_CONFIG_NOSYSTEM=1`.** Disables system-scope git config, which is
  where `core.hooksPath` lives, so it disables the gate. Any committing
  process that sets or inherits this variable bypasses the gate, regardless
  of why it was set.

## Failure handling

The gate never blocks container start: postStart only warns, whether the spec
is missing, misplaced, or a repository's effective `core.hooksPath` shadows
the gate. A missing spec warns at postStart and rejects at commit time; a
malformed spec is not detected at postStart and is caught only at commit
time — the fail-closed behavior described under *Behavior* above. When hook
resolution runs outside a repository (e.g. `reference-transaction` firing
mid-`git init`, before the repository is recognized), nothing is printed: the
transient failure is not leaked to the user.
