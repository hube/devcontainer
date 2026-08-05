# Claude

This local feature installs Claude Code and configures up to four independent
Claude Code accounts (`~/.claude` and `~/.claude-1` through `~/.claude-3`), each
backed by its own named volume, and each sharing the host's `CLAUDE.md` and
`projects` directory through bind mounts this Feature declares from the host's
`~/.claude/CLAUDE.md` and `~/.claude/projects` into every account directory.

## Shared agent instructions

Bulk agent instructions shared across every harness in the container are read
from `~/.agents/instructions`. The shared `CLAUDE.md` points at that path as
plain text. The directory holds three files: `rigor-levels.md`,
`review-dispatch-scope.md`, and `reader-proxy-review-dispatch.md`.

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

**These host paths must exist before you start the container.** Docker rejects a
bind mount whose host source is missing, and that failure breaks container
startup outright — before anything can report it. This Feature binds
`~/.claude/CLAUDE.md` and `~/.claude/projects` into every account directory, so
both must exist on the host even if you never declare the mount above; add
`~/.claude/instructions` to that list once you do. A host that has never run
Claude Code has none of them.

To confirm the mount landed, list the target inside the container — it shows the
three files named above:

```bash
ls ~/.agents/instructions
```

If the mount is absent, the container still starts. Claude Code loads its
always-on `CLAUDE.md` normally, and only the referenced bulk detail is
unavailable.
