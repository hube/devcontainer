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
**consumer-declared**. Copy this block into the top-level `mounts` array of your
`devcontainer.json` — once for the container, not per Feature and not per
account:

```json
{
  "type": "bind,readonly",
  "source": "${localEnv:HOME}/.claude/instructions",
  "target": "/home/${localEnv:USERNAME:devcontainer}/.agents/instructions"
}
```

`devcontainer.json` holds exactly one top-level `mounts` array. If yours already
has one — another Feature's notes may have told you to add an entry to it — put
this entry inside it rather than adding a second `"mounts"` key. A repeated key
is not an error: the file parses, the container builds and starts, and one of
the two arrays is silently discarded along with every mount in it.

**These host paths must exist before you start the container.** Docker rejects a
bind mount whose host source is missing, and that failure breaks container
startup outright — before anything can report it. This Feature binds
`~/.claude/CLAUDE.md` and `~/.claude/projects` into every account directory, so
both must exist on the host even if you never declare the mount above; add
`~/.claude/instructions` to that list once you do. A host that has never run
Claude Code has none of them. Docker names the offending path when this happens:

```
Error response from daemon: invalid mount config for type "bind":
bind source path does not exist: /Users/you/.claude/instructions
```

To confirm the mount landed, list the target inside the container. It must
exist; an empty listing means either nothing was mounted onto it or the host
directory is itself empty, so check the host path before changing any JSON:

```bash
ls -ld ~/.agents/instructions && ls ~/.agents/instructions
```

If you never declare the mount, the container still starts. Claude Code loads
its always-on `CLAUDE.md` normally, and only the referenced bulk detail is
unavailable.
