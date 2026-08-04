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
mounts from the host's shared agent instruction file. Bulk references that file
points at — the rigor-levels reference and the verbatim reviewer dispatch blocks
— are read from `~/.agents/instructions`. The pointer is plain text, not an
`@path` import: Codex reads `AGENTS.md` wholesale and does not expand imports,
so an import would silently do nothing.

This Feature owns only the container **target** path. The mount is
**consumer-declared** — its host source is specific to the Claude configuration
layout — and is declared **once** for the whole container, serving every harness
in it. The declaration and its host prerequisite are documented in the
[Claude feature notes](../claude/NOTES.md).

If the mount is absent the container still starts. The Feature's startup hook
warns on stderr, Codex loads `AGENTS.md` normally, and only the referenced bulk
detail is unavailable.

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
