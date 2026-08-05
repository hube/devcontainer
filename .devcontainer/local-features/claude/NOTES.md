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
**consumer-declared**. Add it once to your `devcontainer.json` — not per Feature
and not per account:

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

One mount serves every harness in the container. Where another Feature's notes
describe this same target path, both describe one declaration: add it once, not
once per Feature.

**The host source directory must exist before you declare the mount.** Docker
rejects a bind mount whose host source is missing, and that failure breaks
container startup outright. Create `~/.claude/instructions` on the host first,
then add the mount.

If the mount is absent, the container still starts. Claude Code loads its
always-on `CLAUDE.md` normally, and only the referenced bulk detail is
unavailable.
