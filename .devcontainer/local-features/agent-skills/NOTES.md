## Behavior

This Feature makes the hube-agent skills available to Claude Code and Codex.
On container start it clones the configured repository if absent, or refreshes
remote refs in an existing clone without merging or moving its working tree.
It then runs `setup.sh claude` and `setup.sh codex` independently: either target
can fail without preventing the other attempt or blocking container start.

By default the remote is [`hube/agent-skills`][1] and the clone lands in
`/workspaces/agent-skills`. Both are options, `repo` and `cloneDir`. The installer
owns harness configuration and conflict checks; the Feature does not replace
user-owned paths or another Codex marketplace registration to force success.

## Prerequisites

Both harness CLIs must be available to the container user. Claude installation
requires `claude --version` to succeed. Codex installation requires a working
`codex` CLI with plugin marketplace support, plus Node.js for payload preparation
and the Feature's bundled caller. The maintained [installer][2] owns the exact
installation requirements.

Cloning uses the forwarded SSH agent. This Feature depends on the `ssh` Feature,
which prepares the socket and `~/.ssh/known_hosts`, and on
`workspaces-permissions`, which makes `/workspaces` writable by the container
user. A missing identity or unreachable remote prevents an initial clone.

## Activate and check skills

Rebuild the consuming container after adopting an image containing this Feature
change. Restart runs the installed hook again; it does not update an existing
skills clone's working tree. To adopt a newer installer, update that clone
through its own repository workflow before restarting. For an immediate retry
inside the container, run:

```bash
~/bin/devcontainer-feature/agent-skills/postStartScript.sh
```

Check the installed state as the container user:

```bash
readlink ~/.claude/skills/hube-agent
codex plugin marketplace list --json
codex plugin list --json
```

The Claude link should resolve to the configured clone. Codex should list the
`hube-agent` marketplace rooted there and the installed `hube-agent` plugin.
Restart Claude Code or use `/reload-plugins`; start a new Codex session to consume
the installed plugin. The hook's zero exit status means startup can continue;
use these readbacks and any diagnostics to establish installation success.

## Recover a failed installation

The hook reports the failing harness and captures the installer's output before
its problem, consequence and remedy. A Claude failure means its skills may not
load; repair the Claude CLI or the named conflicting path, preserve any content
you need, then rerun `bash /workspaces/agent-skills/setup.sh claude`. A Codex
failure means its plugin may not load; repair its CLI or marketplace configuration
as directed, then rerun `bash /workspaces/agent-skills/setup.sh codex`. Substitute
your configured `cloneDir` when different. Either retry changes only that target.

For initial clone failures, restore the forwarded agent identity or repository
access identified in the diagnostic, then rerun the hook. A fetch failure leaves
remote refs stale but installation still uses the existing working tree. Repair
network/repository access and rerun to refresh refs. Conflicting user paths remain
untouched; the installer identifies them instead of silently overwriting them.

## Rebuild persistence

The clone is scratch space. `/workspaces/<project>` is a bind mount of the host
directory you opened, but sibling directories such as `/workspaces/agent-skills`
live on the container filesystem and are destroyed on rebuild. Edit the skills
repository from its own workspace, where it is bind-mounted from the host.

[Maintainer acceptance](MAINTAINERS.md) owns verification of Feature changes.
This is the owning startup reference for
[agent-skills #114](https://github.com/hube/agent-skills/issues/114) and
[#39](https://github.com/hube/agent-skills/issues/39); that repository owns its
installer and plugin documentation.

[1]: https://github.com/hube/agent-skills
[2]: https://github.com/hube/agent-skills/blob/main/setup.sh
