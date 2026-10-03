## Codex Remote Control

Codex remote control requires the container to be reachable via SSH. This local
feature depends on the [sshd feature][1] to launch an ssh server that listens on
port 2222. The consuming devcontainer must then publish that port in order to
reach the container's ssh server, e.g. by adding the following to the
`devcontainer.json` file:

```
{
  ...
  "appPort": ["127.0.0.1:2222:2222"]
}
```

See the [devcontainer documentation][2] for details

## Supported Codex runtime

Docker Desktop in Linux-container mode is the sole supported runtime for the
Codex sandbox integration. Native Linux Docker, rootless Docker, Podman, and
other Dev Container backends are unsupported.

The published image embeds these exact Docker security options:

The exact entries are `seccomp=unconfined` and `apparmor=unconfined`.

```json
"securityOpt": [
  "seccomp=unconfined",
  "apparmor=unconfined"
]
```

The embedded and published `capAdd` is exactly `[]`, so no Docker capabilities
are added. The default-security control must fail through the instrumented system Bubblewrap
path with `bwrap: pivot_root: Operation not permitted`. If that control begins
to pass, it is the retirement signal: reevaluate and redesign the outer runtime
before preserving either unconfined option.

## Outer and inner sandbox boundaries

The feature installs `/usr/bin/bwrap` as `root:root` with mode `4755`. Runtime
acceptance verifies that Codex selects this system executable instead of
Codex's bundled fallback.

The security options create a relaxed outer Docker boundary so Codex can
construct Codex's inner sandbox for commands it launches. The outer relaxation
is container-wide. Interactive shells, lifecycle scripts, and other non-Codex
processes do not receive Codex's inner sandbox and therefore run without its
filesystem isolation or in-process syscall restrictions.

Dev Container tooling merges image metadata with consumer configuration.
Consumer-supplied seccomp or AppArmor values in additional `securityOpt`
entries conflict with the image's settings and are unsupported; remove those
additional entries rather than attempting to override the embedded contract.

## Shared agent instructions

Codex reads its always-on guidance from `~/.codex/AGENTS.md`, which this Feature
mounts from the host's `~/.claude/CLAUDE.md` — a single shared file under two
names, separate from the `~/.agents/instructions` directory mount described
below. Bulk references that file points at are read from
`~/.agents/instructions`. The host must supply the canonical shared instruction
corpus from [hube/claude-home](https://github.com/hube/claude-home), including
`setup-recovery.md` and the worktree and orchestration consumers that reference
it. Updating a separate clone inside the container does not update a host bind
source.

This Feature owns only the container **target** path. The mount itself is
**consumer-declared**: you choose the host directory it reads from. Copy this
block into the top-level `mounts` array of your `devcontainer.json` — once for
the container, not per Feature — with `source` set to that directory:

```json
{
  "type": "bind,readonly",
  "source": "${localEnv:HOME}/agent-instructions",
  "target": "/home/${localEnv:USERNAME:devcontainer}/.agents/instructions"
}
```

**The host directory you name as `source` must exist before you start the
container.** Docker rejects a bind mount whose host source is missing, and that
failure breaks container startup outright — before anything can report it. The
host file this Feature binds as `AGENTS.md` must exist for the same reason.
Docker names the offending path when this happens:

```
Error response from daemon: invalid mount config for type "bind":
bind source path does not exist: /Users/you/agent-instructions
```

To confirm the mount landed, list the target inside the container. It must
exist; an empty listing means either nothing was mounted onto it or the host
directory is itself empty, so check the host path before changing any JSON:

```bash
ls -ld ~/.agents/instructions && ls ~/.agents/instructions
```

If you never declare the mount, the container still starts. Codex loads
`AGENTS.md` normally, and only the referenced bulk detail is unavailable.

## Activate autonomous task startup

Startup recovery lets a desktop remote agent or delegate establish an isolated
branch and linked worktree after an eligible sandbox denial using Codex's
supported automatic approval review. The shared instructions classify the
failure; the running session's policy controls whether approval is available.
This configuration covers isolated task startup. Fetch, task checks, signing,
publication, and migration of incompatible persistent installations have separate
acceptance requirements.

The compatible subset is Docker Desktop in Linux-container mode with the
Feature's existing runtime contract, a readable always-on guidance file and
canonical bulk corpus, and an effective session policy exposing automatic review
and the execution tool's supported escalation argument. Feature defaults select
`approvals_reviewer = "auto_review"`; they do not prove the effective desktop or
delegate policy. A managed or user policy that prevents automatic review needs
an explicit policy decision before startup recovery can be enabled.

With the current canonical corpus installed at the host mount source, check
what the container actually reads. Run these commands in the container as its
configured user:

```bash
cat ~/.codex/AGENTS.md
cat ~/.agents/instructions/setup-recovery.md
cat ~/.agents/instructions/worktree-isolation.md
```

All three reads must succeed. The always-on index must direct setup failures to
`setup-recovery.md`, and the worktree instructions must reference that same
recovery procedure. The recovery file must describe classification, inspection
of task-owned partial effects, and the supported automatic approval path.

Start a fresh desktop remote chat so it loads the refreshed always-on context.
Request a compatibility report from that chat covering its runtime-provided
approval policy and execution tool, and the same values from a real delegate's
own received context. The report must identify `auto_review` and the supported
`require_escalated` argument in both contexts. Missing runtime policy or a missing escalation argument is
a harness integration dependency, even when the config file has the right
value. Availability requires the live parent/delegate startup acceptance in
addition to these input checks.

If a read fails, preserve its stdout/stderr and inspect the mounts in the
container:

```bash
findmnt -T ~/.codex/AGENTS.md
findmnt -T ~/.agents/instructions
```

A missing bulk file means the host source does not supply the required corpus.
Update that host source rather than a container clone. An always-on file that
lists in the directory but fails to read can be a stale single-file bind after
its host source was replaced. Restore the host source named by the mount and
recreate the devcontainer through the consuming project's normal container
lifecycle, then repeat the reads and open a fresh chat. Success means the files
are readable through their configured mounts and the new session consumes them;
a directory listing alone does not establish that.

A terminal startup diagnostic needs the failed command and captured output,
the effective parent/delegate policy, and the verified partial branch/worktree
state from the task's working notes. These distinguish a sandbox denial from an
approval rejection, ownership refusal, authorization failure, or ordinary
command failure. Approval does not supply missing authorization or permit
another task's worktree to be reused.

To roll back the guidance activation, restore the previously selected host
corpus revision and refresh the container's mounts and chat context in the same
way. Keep the persistent Codex volume, unrelated configuration, authentication,
session history, and other tasks' worktrees intact.

## Creation and health failures

If container creation fails before the post-create hook runs, read the failed
`devcontainer up` output first — it is authoritative, and two different causes
land here. If it names a bind source that does not exist, a mount is declared
whose host path is missing; create that path and recreate the container (see
"Shared agent instructions" above). Otherwise Docker Desktop could not apply the
image's published runtime contract: confirm Docker Desktop is running Linux
containers, remove conflicting consumer `securityOpt` entries, and recreate the
container. Preserve the complete CLI output when requesting help.

If the post-create health check fails, Codex could not validate the ownership
and mode of system Bubblewrap or could not create and read a marker through
`codex sandbox -P :workspace`. Follow the problem, consequence, and remedy in
the hook diagnostic; its final clause contains the captured `stat`, Codex, or
cleanup output. Correct the reported installation or runtime problem, rebuild
the container, and rerun creation. There is no automatic fallback to a custom
profile, a different image, or an unsandboxed Codex command.

## Maintainer documentation

Maintainers can find local acceptance, publication, post-publication,
cleanup, and retirement procedures in the [maintenance guide](MAINTAINERS.md).

[1]: https://github.com/devcontainers/features/tree/main/src/sshd
[2]: https://containers.dev/implementors/json_reference/#image-specific
