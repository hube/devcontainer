# Claude

This local feature installs Claude Code and configures up to four independent
Claude Code accounts (`~/.claude` and `~/.claude-1` through `~/.claude-3`), each
backed by its own named volume, and each sharing the host's `CLAUDE.md` and
`projects` directory through bind mounts this Feature declares from the host's
`~/.claude/CLAUDE.md` and `~/.claude/projects` into every account directory.

## Shared agent instructions

Bulk agent instructions shared across every harness in the container — the
rigor-levels reference and the verbatim reviewer dispatch blocks — are read from
`~/.agents/instructions`. The shared `CLAUDE.md` points at that path as plain
text.

This Feature owns only the container **target** path. The mount itself is
**consumer-declared**: its host source `~/.claude/instructions` is specific to
the Claude configuration layout, and hardcoding it in a Feature would leak that
layout into otherwise neutral Feature source and give the single target
duplicate owners. Add it once to your `devcontainer.json` — in this repository
that is `.devcontainer/devcontainer.json`; a project consuming the published
image adds it to that project's own `.devcontainer/devcontainer.json` — not per
Feature and not per account:

```json
{
  "mounts": [
    {
      "type": "bind,readonly",
      "source": "${localEnv:HOME}/.claude/instructions",
      "target": "/home/${localEnv:USERNAME:devcontainer}/.agents/instructions"
    }
  ]
}
```

One mount serves every harness in the container: the Codex feature reads the
same target path. The mount is read-only because the instructions are read,
never written, so no approved command in any harness can alter them through it.

**The host directory must exist before you declare the mount.** Docker rejects a
bind mount whose host source is missing, and that failure breaks container
startup outright — before any startup warning could run. Create or deploy
`~/.claude/instructions` on the host first, then add the mount. The directory
and its contents live in the `hube/claude-home` repository, whose tracked files
are deployed to the host's `~/.claude`; deploying that repository's
`instructions/` directory is what creates the host path this mount reads.

If the mount is absent, the container still starts. The Feature's startup hook
warns on stderr during container start, so the message appears wherever your
Dev Containers tooling surfaces startup output — for the CLI, the
`devcontainer up` output. Claude Code loads its always-on `CLAUDE.md` normally,
and only the referenced bulk detail is unavailable.
