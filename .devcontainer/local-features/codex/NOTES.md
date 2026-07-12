## Behavior

This feature installs the Codex CLI, and configures the container so Codex can
actually edit files in it.

Codex applies every patch inside a [Bubblewrap][1] sandbox, which has to create
an unprivileged user namespace. Docker's default seccomp profile denies that, so
without this configuration Codex fails on its first edit and cannot write
anything (hube/devcontainer#36).

The feature therefore ships its own seccomp profile, `seccomp/userns.json`, and
activates it through its own `securityOpt`. Nothing needs to be added to
`devcontainer.json` — no `runArgs`, no `--security-opt`. Installing this feature
is the whole configuration.

The profile is read **from the host** when the container is created, so the
feature has to be referenced by relative path (`./local-features/codex`) from a
checkout of this repository. That is how `devcontainer.json` already consumes it.
The path travels with the feature, so the two cannot drift apart.

`seccomp/README.md` records where the profile came from, exactly what was changed
relative to upstream, and how to re-vendor it.

## Failure handling

On container create the feature probes the capability it depends on: it creates
a user namespace with `unshare`, then starts a Bubblewrap sandbox. Every applicable check runs even after another fails. If either probe fails, or if the required `bwrap` executable is missing, **container
create fails**, naming the problem, the consequence, the targeted remedy, and
the underlying command output. A missing executable points to installing the
`bubblewrap` package and rebuilding; a blocked probe points to `securityOpt`.

This is deliberately stricter than the `agent-skills` feature, which never fails
container start. A Codex feature whose patch helper cannot run is not degraded,
it is broken — and starting quietly would only move the failure into the middle
of a Codex session, which is the symptom that made the original bug so confusing.

The feature explicitly installs the system `bubblewrap` package because `bwrap` is the stable feature probe. Codex's version-scoped copies under `~/.codex/packages/.../codex-resources/bwrap` are internal and unstable. Official OpenAI Dev Container guidance also installs Bubblewrap independently.

The stock-profile test intentionally fails if Docker's default profile becomes sufficient; that is the retirement signal to reevaluate and remove these relaxations. There is no stable documented Codex interface that signals Codex stopped using Bubblewrap, so this feature does not inspect versioned internal package paths or add an upstream watcher.

## Caveats

The seccomp relaxation is container-wide, not Codex-specific: any process in the
container can create user namespaces and call the mount-family syscalls. It is
still far narrower than `seccomp=unconfined` — every other syscall the default
profile denies stays denied — but it is a real widening, and it is the price of
running a sandboxing tool inside a sandbox.

The profile is only known to be needed on Docker Desktop hosts. On Linux hosts
with AppArmor (Ubuntu 23.10+), unprivileged user namespaces are restricted by
AppArmor as well, and seccomp alone would not be enough.

[1]: https://github.com/containers/bubblewrap
