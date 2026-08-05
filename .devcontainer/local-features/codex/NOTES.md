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
`~/.agents/instructions`, which holds three files: `rigor-levels.md`,
`review-dispatch-scope.md`, and `reader-proxy-review-dispatch.md`.

This Feature owns only the container **target** path. The mount itself is
**consumer-declared**. Add it once to your `devcontainer.json` — not per
Feature:

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
container startup outright — before anything can report it. Create
`~/.claude/instructions` on the host first, then add the mount. The host file
this Feature binds as `AGENTS.md` must exist for the same reason.

To confirm the mount landed, list the target inside the container — it shows the
three files named above:

```bash
ls ~/.agents/instructions
```

If the mount is absent, the container still starts. Codex loads `AGENTS.md`
normally, and only the referenced bulk detail is unavailable.

## Creation and health failures

If container creation fails before the post-create hook runs, Docker Desktop
could not apply the image's published runtime contract. The failed
`devcontainer up` output is authoritative. Confirm Docker Desktop is running
Linux containers, remove conflicting consumer `securityOpt` entries, and
recreate the container. Preserve the complete CLI output when requesting help.

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
