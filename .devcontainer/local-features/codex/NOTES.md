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

The controlled Docker Desktop capability-subtraction test produced an empty
final set, so the Codex feature does not add Docker capabilities. The
default-security control must fail through the instrumented system Bubblewrap
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

## Docker Desktop acceptance

Before publication, build and validate a stable local tag from the repository
root, then exercise that tag from an unrelated temporary workspace:

```bash
CODEX_RUNTIME_TEST_IMAGE=codex-runtime-test:task-4 \
  bash .devcontainer/local-features/codex/test/test-runtime.sh
bash .devcontainer/local-features/codex/test/test-image-consumer.sh \
  codex-runtime-test:task-4
```

The local consumer acceptance command is
`test-image-consumer.sh codex-runtime-test:task-4` from the test directory.

After merge and publication, exercise the original consumer path separately:

```bash
bash .devcontainer/local-features/codex/test/test-image-consumer.sh \
  ghcr.io/hube/devcontainer:latest
```

The post-publication consumer acceptance command is
`test-image-consumer.sh ghcr.io/hube/devcontainer:latest` from the test
directory.

The local command validates the implementation but does not establish that the
published tag contains it. Treat the publication check as pending until its
command actually succeeds on Docker Desktop.

[1]: https://github.com/devcontainers/features/tree/main/src/sshd
[2]: https://containers.dev/implementors/json_reference/#image-specific
