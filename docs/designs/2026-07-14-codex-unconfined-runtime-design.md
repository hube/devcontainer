# Run Codex's Bubblewrap sandbox inside the published devcontainer image

**Status:** Design direction approved; written design under review.

Supersedes
[`2026-07-11-codex-bwrap-user-namespaces-design.md`](2026-07-11-codex-bwrap-user-namespaces-design.md)
and
[`2026-07-12-codex-bwrap-user-namespaces-implementation-plan.md`](../implementation-plans/2026-07-12-codex-bwrap-user-namespaces-implementation-plan.md),
and resolves the remaining work in
[`issue #36`](https://github.com/hube/devcontainer/issues/36).

## Problem

Codex uses Bubblewrap for its Linux filesystem sandbox. Docker's default
seccomp policy blocks the namespace and mount operations Bubblewrap needs, so
Codex cannot apply patches in this devcontainer.

The first design addressed that restriction with a custom seccomp profile in
the Codex local Feature. The profile worked when this repository was the
consumer, but the published image embedded a `securityOpt` value pointing into
`${localWorkspaceFolder}`. An unrelated project consuming only
`ghcr.io/hube/devcontainer:latest` has no copy of that local Feature file, so
Docker failed before starting the container. The implementation was reverted
in [PR #42](https://github.com/hube/devcontainer/pull/42).

The replacement must satisfy all of these constraints:

- projects that specify only the published image receive a working Codex
  sandbox without copying host-side support files;
- Codex continues to run as the non-root container user;
- the same image supports Docker Desktop and native Linux Docker;
- failures surface during container creation with the underlying command
  output;
- Docker runtime relaxations are explicit, documented, and removable when no
  longer necessary.

## Decisions

### One published image remains the product boundary

**Decided (owner, 2026-07-14, in session):** apply the fix to the existing
Codex local Feature and published `latest` image rather than introducing a
second image or profile.

The Feature owns every setting needed by Codex. Its metadata is embedded in the
published image, so downstream projects inherit the configuration without
adding Features or `runArgs` of their own.

No Feature metadata may reference `${localWorkspaceFolder}` or another
host-side support file. The runtime policy consists only of self-contained
Docker options.

### Relax Docker's outer sandbox so Codex can create its inner sandbox

**Decided (owner, 2026-07-14, in session):** the Codex Feature contributes:

```json
"securityOpt": [
  "seccomp=unconfined",
  "apparmor=unconfined"
]
```

Docker therefore does not apply its default seccomp or AppArmor profiles to
the development container. Codex still launches commands through its own
Bubblewrap filesystem sandbox and in-process seccomp restrictions.

This follows the explicit model in OpenAI's
[`devcontainer.secure.json`](https://github.com/openai/codex/blob/main/.devcontainer/devcontainer.secure.json):
the outer Docker restrictions are relaxed so the inner Codex sandbox can be
constructed. The choice is broader than the previous custom profile, but its
configuration is standard, visible in image metadata, and independent of the
consumer's filesystem.

The relaxation is container-wide. Interactive shells, lifecycle scripts, and
non-Codex processes do not automatically receive Codex's inner sandbox. The
Feature documentation must state this consequence directly.

### Use a setuid system Bubblewrap and retain only required capabilities

**Decided (owner, 2026-07-14, in session):** the Feature explicitly installs
the distribution `bubblewrap` package and sets the setuid bit on
`/usr/bin/bwrap`. Codex uses the first `bwrap` executable on `PATH`, giving the
Feature a stable executable independent of Codex's versioned internal package
layout.

The Feature also contributes the minimum Docker capability set required for
that executable and the current Codex sandbox path. Implementation starts from
the capability candidates used by OpenAI's secure devcontainer:

- `SYS_ADMIN`
- `SYS_CHROOT`
- `SETUID`
- `SETGID`
- `SYS_PTRACE`

The committed set is determined by controlled subtraction. A baseline using
all candidates must pass the end-to-end Codex sandbox probe. Each candidate is
then removed in isolation. A capability is retained only when its removal
causes that same probe to fail and restoring it makes the probe pass again. The
final set is rerun as a whole. This process prevents unrelated capabilities in
the upstream development image from being copied without a demonstrated
dependency.

`NET_ADMIN` and `NET_RAW` are not candidates. OpenAI uses them for its
container firewall, not for Bubblewrap.

### Support Docker Desktop and native Linux Docker

**Decided (owner, 2026-07-14, in session):** both Docker Desktop and native
Linux Docker are supported targets.

The supported runtime contract is Docker Desktop in Linux-container mode or a
rootful native Docker Engine that accepts the declared capabilities and
security options. Rootless Docker, Podman, and other Dev Container backends are
out of scope for this change because their privilege and LSM models differ.

`seccomp=unconfined` addresses the Docker seccomp restriction on both targets.
`apparmor=unconfined` addresses native Linux hosts where Docker's AppArmor
profile blocks Bubblewrap. Hosts that do not enforce AppArmor still receive the
same declarative configuration; compatibility is verified by container-create
tests rather than inferred from the host name.

Native Linux behavior is automated in CI. Docker Desktop requires a one-time
manual acceptance run because the repository's Linux CI runner cannot emulate
Docker Desktop's Linux VM and host integration.

### Define health by Codex's sandbox, not by a preliminary syscall probe

**Decided (owner, 2026-07-14, in session):** container creation is healthy only
when the installed Codex CLI can launch a harmless command through its Linux
sandbox.

The Feature installs a `postCreateCommand` health script under
`~/bin/devcontainer-feature/codex/`. The script:

1. confirms that `/usr/bin/bwrap` exists, is owned by root, and has the setuid
   bit;
2. invokes the installed CLI's `codex sandbox` surface in a temporary working
   directory;
3. requires the sandboxed command to create and read a marker in its allowed
   working directory;
4. removes the temporary directory and exits once with the aggregate result.

The probe does not authenticate or call a model. It exercises the Codex-owned
sandbox launcher that the patch helper relies on while remaining deterministic
and usable during container creation.

A direct `bwrap` command remains a diagnostic and test fixture, not the health
contract. If the Codex probe fails, the script may run direct Bubblewrap to
distinguish installation/runtime failure from a Codex CLI integration failure.

The CLI is intentionally installed from OpenAI's unpinned installer in the
current project. Consequently the health script is allowed to fail when a new
Codex release changes its sandbox interface: that failure prevents publishing
or silently starting an image whose Codex integration has not been updated.
The publish workflow must run the same sandbox verification before its image
push step; the lifecycle hook alone would detect the problem only after a
consumer pulled the image.

## Components and data flow

### Feature metadata

`.devcontainer/local-features/codex/devcontainer-feature.json` contributes:

- the two `securityOpt` entries;
- the capability set established by the controlled tests;
- the post-create health command;
- the existing mounts and sshd dependency.

During the repository image build, Dev Container tooling writes this Feature
metadata into the image's `devcontainer.metadata` label. When another project
uses the image, the Dev Container CLI merges the label into that project's
configuration and emits self-contained Docker flags. No file lookup crosses
from the image into the consumer checkout.

### Feature installation

`.devcontainer/local-features/codex/install.sh` performs root-only work before
re-executing as the container user:

1. install `bubblewrap` explicitly;
2. set and verify root ownership and the setuid mode on `/usr/bin/bwrap`;
3. copy the Feature's home and health-script files with the existing ownership
   rules;
4. re-execute as the container user and install Codex as today.

The installer fails immediately if package installation, ownership, or mode
verification fails. It must include the underlying command output.

### Container creation

The consumer starts from `ghcr.io/hube/devcontainer:latest`. Image metadata
adds the security options and tested capabilities before Docker creates the
container. After creation, the health script verifies that Codex can use those
runtime permissions. A failure stops the create workflow rather than moving
the first visible error into an agent session.

## Error handling

Every Feature-owned error states, in order:

1. the problem;
2. the consequence for Codex;
3. the remedy;
4. the captured stdout/stderr from the command that failed.

The health script collects independent applicable failures before returning a
single non-zero status. It does not ask the user to rerun a command whose output
it already captured.

Docker may reject a security option or capability before the health script can
run. In that case Docker's container-create error is the authoritative output;
the Feature notes must explain that the host does not support the published
runtime contract and that the remedy is to use a supported Docker Desktop or
native Linux Docker configuration.

There is no automatic fallback to deprecated Landlock, `danger-full-access`, a
custom profile, or a different image. Falling back would either weaken the
selected security model silently or reintroduce the distribution failure.

## Verification

The implementation provides four layers of verification.

### Structural Feature tests

- Parse Feature metadata and assert the exact `securityOpt`, capability, and
  `postCreateCommand` values.
- Reject any seccomp value containing a filesystem path.
- Assert that the installer installs `bubblewrap` and sets/verifies the setuid
  mode before re-executing as the non-root user.
- Mutation-check assertions whose labels claim to prove package installation
  or mode changes so comments alone cannot satisfy them.

### Built-image tests

- Build the devcontainer image under a unique temporary tag.
- Inspect `devcontainer.metadata` and confirm the Codex settings survive the
  image boundary.
- Inspect `/usr/bin/bwrap` as the non-root runtime image and confirm its owner
  and mode.
- Preserve and print build output on failure; remove temporary images through
  cleanup traps.

### Native Linux behavioral tests

- Establish a control using Docker's default security settings and require it
  to reproduce the relevant Bubblewrap restriction. If the control begins to
  pass, fail with a retirement message so the relaxations are reevaluated.
- Establish a treatment with both unconfined security options and the full
  capability candidate set; require the Codex sandbox probe to pass.
- Run the controlled capability-subtraction matrix and final minimal set.
- Run the Feature health script's success and failure paths with distinct
  captured-output sentinels.

The control and treatment use the same built image, command, user, and working
directory; only the runtime security configuration changes. This rules out a
different image or probe command as the benign explanation for the observed
behavior.

### Docker Desktop acceptance

After merge and publication:

1. create an unrelated project whose `devcontainer.json` specifies only
   `ghcr.io/hube/devcontainer:latest` plus its application port;
2. run `devcontainer up` on Docker Desktop;
3. confirm the post-create Codex sandbox probe succeeds;
4. invoke Codex's patch helper against a tracked file in a worktree and confirm
   the edit persists.

Issue #36 closes only after this reproduces the original image-consumer path,
not merely the source repository's local Feature path.

## Documentation and lifecycle

The Codex Feature `NOTES.md` and repository `README.md` describe:

- that the published image enables a setuid Bubblewrap sandbox for Codex;
- the exact Docker security options and capabilities ultimately retained;
- the distinction between Docker's relaxed outer boundary and Codex's inner
  sandbox;
- supported host families and failure remedies;
- the control test as the retirement signal.

The previous custom-profile design and its implementation plan remain in the
repository as historical records with prominent supersession notices linking
to this design. The replacement implementation plan is written from this
design alone.

## Out of scope

**Decided (owner, 2026-07-14, in session):** this change does not add a
container firewall, pin Codex or the base image, introduce a second published
image, or change Docker-outside-of-Docker. Those concerns require separate
designs because they alter independent trust and update boundaries.

## Risks and trade-offs

- Docker's outer seccomp and AppArmor protections are disabled for every
  process in the container, and the retained capabilities are container-wide.
  Only commands launched by Codex receive Codex's inner sandbox.
- A setuid executable adds a privileged code path. Installing the distribution
  package provides a stable, host-independent binary, but package updates can
  change behavior and must be caught by the behavioral tests.
- The unpinned Codex installer can change the sandbox CLI contract between
  image builds. Failing image or post-create tests are the deliberate signal to
  update the integration.
- Native Linux distributions and Docker Desktop releases can differ in kernel
  and LSM behavior. The two-host acceptance model makes that difference
  explicit rather than claiming one environment represents both.
