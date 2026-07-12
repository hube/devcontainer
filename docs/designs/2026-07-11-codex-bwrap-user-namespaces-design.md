# Enable unprivileged user namespaces for Codex's patch helper

**Status:** Implemented. Plan:
`docs/implementation-plans/2026-07-12-codex-bwrap-user-namespaces-implementation-plan.md`.

Resolves [issue #36](https://github.com/hube/devcontainer/issues/36).

## Problem

Codex's patch helper wraps repository edits in Bubblewrap (`bwrap`), which
must create an unprivileged user namespace. Inside this devcontainer that
fails before any patch is applied:

```text
bwrap: No permissions to create a new namespace, likely because the kernel does not allow non-privileged user namespaces.
```

Root cause, verified by differential reproduction on the in-scope Docker
Desktop host (Docker Engine 29.3.1, kernel 6.12.76-linuxkit):

```console
$ docker run --rm ubuntu:rolling unshare --user --map-root-user true
unshare: unshare failed: Operation not permitted

$ docker run --rm --security-opt seccomp=unconfined ubuntu:rolling \
    unshare --user --map-root-user true
# exits 0
```

The only variable between the two runs is the seccomp profile, so the
built-in profile is the blocker — the kernel permits unprivileged user
namespaces and no other LSM intervenes (`docker info` reports only
`name=seccomp,profile=builtin name=cgroupns` under SecurityOptions).
Supporting observations from the running devcontainer: `unshare --user`
fails the same way, and `devcontainer.json` passes no `runArgs`, so nothing
overrides the default profile.

Docker's default seccomp profile denies `clone`/`unshare` with `CLONE_NEW*`
flags for containers without `CAP_SYS_ADMIN`, which is exactly the syscall
Bubblewrap needs. This is an environment restriction, not a Codex bug.

## Decision

Fix the environment rather than reconfiguring Codex: run the container under
a custom seccomp profile — a vendored, pinned copy of Docker's default
profile with targeted edits that permit unprivileged user namespaces and the
syscalls Bubblewrap uses inside them.

Only Codex needs this capability, so everything that supports it — the
profile, its provenance record, the `securityOpt` that activates it, the
create-time smoke test, and the `NOTES.md` describing how to configure the
feature — lives in the Codex local feature
(`.devcontainer/local-features/codex/`). The top-level `devcontainer.json`
is not modified at all.

Alternatives considered and rejected:

- **Configure Codex to skip its internal sandbox** (treat the container as
  the isolation boundary). Rejected in favor of fixing Bubblewrap for every
  tool in the container.
- **`--security-opt seccomp=unconfined`**: simplest, but disables all syscall
  filtering rather than just the user-namespace block.
- **`--privileged`**: grants far more than needed.
- **Generating the profile at create time** from upstream: avoids staleness
  but adds host tooling (`curl`, `jq`), a network dependency at container
  create, and an unauditable generated artifact.

Scope: Docker Desktop hosts only. No AppArmor handling (Ubuntu 23.10+ hosts
additionally restrict unprivileged user namespaces via AppArmor and would
need more; that is out of scope until such a host is actually used).

## Design

### 1. Vendored seccomp profile — `.devcontainer/local-features/codex/seccomp/userns.json` (new)

A copy of Moby's default seccomp profile, edited as described below. The
profile no longer lives in `moby/moby` (the path `profiles/seccomp/default.json`
is absent from current release tags); it is now published in the
independently versioned [`moby/profiles`](https://github.com/moby/profiles)
repository. Vendor `seccomp/default.json` from the latest `seccomp/vX.Y.Z`
release tag at implementation time (currently `seccomp/v0.2.3`, SHA-256
`536529b665dd0972c37bfb569f5d4ac8a53592e7b00752bc39ff063ca9864c74`), recording
the tag and checksum in the README. No engine-version mapping is needed: the
profiles repository tracks current engines, and the create-time smoke test
(section 4) validates the profile against whatever engine Docker Desktop is
actually running.

The upstream profile's `defaultAction` is `SCMP_ACT_ERRNO`, so a syscall is
permitted only if some rule allows it. Three distinct edits are needed, and
they must not be conflated — they start from different upstream states:

- **Ungate four capability-gated syscalls.** `mount`, `umount2`, `setns`, and
  `unshare` are allowed by a rule whose `includes.caps` is `CAP_SYS_ADMIN`.
  Allow them unconditionally.
- **Newly allow `pivot_root`.** It appears nowhere in the profile, so it is
  denied by the default action rather than capability-gated. This genuinely
  widens the allowlist beyond what any capability grants today.
- **Drop the `clone` argument filter.** The non-`CAP_SYS_ADMIN` `clone` rule
  allows the call only when `(flags & 0x7e020000) == 0` — that mask is exactly
  the `CLONE_NEW*` namespace bits. Removing the filter is what permits
  `CLONE_NEWUSER`.

`clone3` is deliberately left alone. Upstream returns `ENOSYS` for it without
`CAP_SYS_ADMIN` (seccomp cannot inspect `clone3`'s flags, which sit behind a
userspace pointer), which makes glibc fall back to `clone` — where the
argument filter above *can* be enforced. Preserving that fallback keeps the
namespace path filterable instead of opening an unfilterable one.

The mount-family syscalls are required, not optional: Docker compiles the
seccomp filter from the container's bounding capabilities at start time, so
the `CAP_SYS_ADMIN` that Bubblewrap gains *inside* its new user namespace is
invisible to the filter. Allowing only `unshare`/`clone` would let bwrap
create the namespace and then fail at `mount`/`pivot_root`.

Everything else in the default profile is unchanged; all other denied
syscalls stay denied.

### 2. Provenance record — `.devcontainer/local-features/codex/seccomp/README.md` (new)

JSON cannot carry comments, so a README alongside the profile records:

- the upstream source URL (`moby/profiles`) and the pinned `seccomp/vX.Y.Z`
  release tag;
- the SHA-256 checksum of the unmodified upstream file;
- the exact list of edits relative to upstream, distinguishing the ungated
  syscalls from the newly-allowed `pivot_root` and the `clone` filter removal;
- the re-vendoring procedure: download the pinned upstream file, verify the
  checksum, re-apply the documented edits, and review the diff.

### 3. Wire-up — the Codex feature's `devcontainer-feature.json`

The feature activates the profile itself; no `runArgs` in `devcontainer.json`:

```json
"securityOpt": [
  "seccomp=${localWorkspaceFolder}/.devcontainer/local-features/codex/seccomp/userns.json"
]
```

This works because the Dev Container spec lets a feature contribute
`securityOpt` (it is in the feature schema alongside `privileged` and
`capAdd`), the CLI unions every feature's `securityOpt` into the merged
config, and passes each one to `docker run` as `--security-opt`
(`mergeConfiguration` → `singleContainer.ts`). Feature metadata goes through
the same variable substitution as `devcontainer.json`, so
`${localWorkspaceFolder}` resolves to the host path of the checkout — which
is what `--security-opt seccomp=<path>` needs, since the Docker CLI reads
the profile from the host filesystem at container-create time. The existing
feature already relies on this substitution for its `mounts`.

The path is stable because the profile ships inside the feature and the
feature is consumed by relative path (`./local-features/codex`) from this
repo, so the two always travel together.

Caveat: the CLI does not pass `--security-opt` under the `wslc` variant.
That is out of scope here (Docker Desktop only), but it is why the smoke
test in section 4 checks the capability at runtime rather than assuming the
profile took effect.

### 4. Smoke test in the Codex local feature

Following the pattern the `agent-skills` feature already uses, `install.sh`
installs a verification script under `~/bin/devcontainer-feature/codex/`, and
`devcontainer-feature.json` declares a `postCreateCommand` pointing at it, so
it runs on every container create.

The script runs:

1. `unshare --user --map-root-user true` — user-namespace creation works;
2. `bwrap --unshare-all --dev-bind / / true` — the full Bubblewrap path
   works, including the mount-family syscalls.

On failure it prints problem → consequence → remedy, including the failing
command's actual stderr — e.g. "user-namespace creation is blocked → Codex's
patch helper cannot apply edits → confirm the Codex feature's `securityOpt`
resolves to `local-features/codex/seccomp/userns.json` and rebuild the
container" — and exits non-zero so the failure surfaces at create time
instead of mid-session.

Unlike `agent-skills`, which never fails container start, this check *does*
fail the create: a Codex feature that cannot run Codex's patch helper is
broken, and silently starting would just relocate the failure to the middle
of a session — the exact symptom issue #36 reports.

The test uses the system `bwrap`. It reaches the image through `common-utils`'s
package list, but the Codex feature installs `bubblewrap` explicitly rather than
inherit a load-bearing binary from another feature's incidental dependencies.
Codex also bundles its own `bwrap` under `~/.codex`, which the test deliberately
ignores: that path is version-scoped to Codex's release layout, and both
binaries hit the same kernel/seccomp boundary, so the system one is a faithful
proxy.

### 5. Feature documentation — `.devcontainer/local-features/codex/NOTES.md` (new)

The Codex feature has no `NOTES.md` today. Add one, following the structure
`agent-skills/NOTES.md` established (Behavior / Failure handling / Caveats),
covering how to configure the feature correctly:

- that the feature ships and activates its own seccomp profile via
  `securityOpt`, and therefore requires no `runArgs` in `devcontainer.json`;
- that the profile is resolved from the host checkout at container-create
  time, so the feature must be consumed by relative path from this repo;
- what the create-time smoke test checks and what a failure means;
- the security trade-off (container-wide user namespaces) and a pointer to
  the provenance README for re-vendoring.

## Error handling

- Missing or malformed profile file: `docker run` fails at container create
  with Docker's own error naming the seccomp file. No fallback logic — a
  broken profile must fail loudly, never silently run under a different
  policy.
- Smoke-test failure: container create reports it immediately (see above).

## Verification

Automated, on every container create: the smoke test in the Codex feature.

The implementation tests must not be able to pass against stale artifacts. A
behavioral test that builds a container image uses a unique temporary tag,
stops and preserves Docker's output if the build fails, and removes the image
from an `EXIT` trap. The final test-suite command runs every test but records
any failure and exits non-zero after the suite completes.

Every warning and error emitted by the seccomp-profile or feature-metadata
implementation tests states the problem, its consequence, and a remedy, then
includes the failing command's actual output under a wrapper-owned `<command>
said:` prefix. The tests distinguish failure modes that need different
diagnoses; their diagnostic contracts assert on that wrapper framing rather
than on bare child-process stderr. In particular, the metadata test separately
reports Dev Container build, Docker inspect, JSON parse, and semantic metadata
failures while preserving the exact `securityOpt` and `postCreateCommand`
assertions against the real built image label.

Manual, once after the first rebuild: run Codex's patch helper against a
tracked file in a worktree — the original reproduction from issue #36 — and
confirm the edit persists.

## Implementation workflow

Before each task commit, the executor reruns that task's exact verification,
checks the forwarded signing agent with `ssh-add -l`, and inspects `git status`
and `git diff`. Only the task's listed files are staged. Commit metadata records
the skills actually used by that executor rather than assuming a particular
execution workflow.

## Risks and trade-offs

- The relaxation is container-wide, not Codex-specific: any process in the
  container can now create user namespaces and call the mount-family
  syscalls. Accepted trade-off; still far tighter than `seccomp=unconfined`.
- The vendored profile can drift from upstream as Docker adds newly-allowed
  syscalls for new kernels/glibc. The failure mode is benign and visible
  (a new syscall returns EPERM); the remedy is the re-vendoring procedure in
  the README.
