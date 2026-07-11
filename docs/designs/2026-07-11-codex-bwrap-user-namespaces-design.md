# Enable unprivileged user namespaces for Codex's patch helper

**Status:** Design approved; implementation plan not yet written.

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

### 1. Vendored seccomp profile — `.devcontainer/seccomp/userns.json` (new)

A copy of Moby's default seccomp profile, edited as described below. The
profile no longer lives in `moby/moby` (the path `profiles/seccomp/default.json`
is absent from current release tags); it is now published in the
independently versioned [`moby/profiles`](https://github.com/moby/profiles)
repository. Vendor `seccomp/default.json` from the latest `seccomp/vX.Y.Z`
release tag at implementation time (currently `seccomp/v0.2.3`), recording
the tag and the file's SHA-256 checksum in the README. No engine-version
mapping is needed: the profiles repository tracks current engines, and the
create-time smoke test (section 4) validates the profile against whatever
engine Docker Desktop is actually running. Edits relative to upstream:

- add `unshare`, `setns`, `mount`, `umount2`, and `pivot_root` to the
  unconditional syscall allowlist (the stock profile allows them only when
  the container has `CAP_SYS_ADMIN`);
- drop the argument filter on the `clone` rule that rejects `CLONE_NEW*`
  flags.

The mount-family syscalls are required, not optional: Docker compiles the
seccomp filter from the container's bounding capabilities at start time, so
the `CAP_SYS_ADMIN` that Bubblewrap gains *inside* its new user namespace is
invisible to the filter. Allowing only `unshare`/`clone` would let bwrap
create the namespace and then fail at `mount`/`pivot_root`.

Everything else in the default profile is unchanged; all other denied
syscalls stay denied.

### 2. Provenance record — `.devcontainer/seccomp/README.md` (new)

JSON cannot carry comments, so a README alongside the profile records:

- the upstream source URL (`moby/profiles`) and the pinned `seccomp/vX.Y.Z`
  release tag;
- the SHA-256 checksum of the unmodified upstream file;
- the exact list of edits relative to upstream;
- the re-vendoring procedure: download the pinned upstream file, verify the
  checksum, re-apply the documented edits, and review the diff.

### 3. Wire-up — `devcontainer.json`

```json
"runArgs": [
  "--security-opt",
  "seccomp=${localWorkspaceFolder}/.devcontainer/seccomp/userns.json"
]
```

`runArgs` is passed to `docker run` at container create time; the change
takes effect on the next rebuild and needs nothing further from the host.

### 4. Smoke test in the Codex local feature

Only Codex cares about this capability, so the check lives in
`.devcontainer/local-features/codex/`, not top-level `devcontainer.json`:

- `install.sh` installs a verification script into the image;
- the feature's `devcontainer-feature.json` declares a `postCreateCommand`
  lifecycle hook (features may contribute lifecycle hooks) that runs it on
  every container create.

The script runs:

1. `unshare --user --map-root-user true` — user-namespace creation works;
2. `bwrap --unshare-all --dev-bind / / true` — the full Bubblewrap path
   works, including the mount-family syscalls.

On failure it prints problem → consequence → remedy, including the failing
command's actual stderr (e.g. "user-namespace creation is blocked → Codex's
patch helper cannot apply edits → check that `runArgs` references
`.devcontainer/seccomp/userns.json` and rebuild the container"), and exits
non-zero so the failure surfaces at create time instead of mid-session.

The test uses the system `bwrap` (`/usr/bin/bwrap`, already present in the
image); Codex bundles its own copy, but both hit the same kernel/seccomp
boundary, so the system binary is a faithful proxy.

## Error handling

- Missing or malformed profile file: `docker run` fails at container create
  with Docker's own error naming the seccomp file. No fallback logic — a
  broken profile must fail loudly, never silently run under a different
  policy.
- Smoke-test failure: container create reports it immediately (see above).

## Verification

Automated, on every container create: the smoke test in the Codex feature.

Manual, once after the first rebuild: run Codex's patch helper against a
tracked file in a worktree — the original reproduction from issue #36 — and
confirm the edit persists.

## Risks and trade-offs

- The relaxation is container-wide, not Codex-specific: any process in the
  container can now create user namespaces and call the mount-family
  syscalls. Accepted trade-off; still far tighter than `seccomp=unconfined`.
- The vendored profile can drift from upstream as Docker adds newly-allowed
  syscalls for new kernels/glibc. The failure mode is benign and visible
  (a new syscall returns EPERM); the remedy is the re-vendoring procedure in
  the README.
