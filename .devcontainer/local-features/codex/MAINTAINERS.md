# Maintaining the Codex local Feature

This is the operational authority for accepting and publishing Codex local
Feature changes. User-facing runtime requirements and troubleshooting remain
in [`NOTES.md`](NOTES.md).

Run every command from the repository root with Docker Desktop in
Linux-container mode. The runtime test rejects native Linux Docker, rootless
Docker, Podman, and other engines because they are not supported acceptance
targets.

## Local acceptance

Use a stable local image name so the runtime matrix and unrelated-consumer test
exercise the same build:

```bash
CODEX_RUNTIME_TEST_IMAGE=codex-runtime-test:acceptance \
  bash .devcontainer/local-features/codex/test/test-runtime.sh
bash .devcontainer/local-features/codex/test/test-image-consumer.sh codex-runtime-test:acceptance
bash .devcontainer/local-features/agent-skills/test/test-install-order.sh
```

Acceptance requires all three commands to exit zero. The runtime matrix must
show the default-security control failing through system Bubblewrap with
`bwrap: pivot_root: Operation not permitted`, every treatment and restoration
passing, and a final `REQUIRED_CAPABILITIES=` line matching the committed
`capAdd`. The unrelated consumer must report successful post-create health and
sandboxed patch persistence. The install-order test must report that feature
install order and the combined lifecycle command were verified.

If a command fails, the problem is that the supported-runtime contract has not
been accepted; merging could publish an image whose Codex sandbox is unusable.
Preserve the complete output, correct the reported build, Docker, cleanup, or
sandbox failure, and rerun all three commands before merging.

## Verify autonomous task startup

This live acceptance exercises the desktop remote parent and a real delegate,
using disposable Git state. It complements the repository-input checks; a
standalone CLI probe does not establish desktop or delegated approval.

Run the input checks from a task-linked worktree of this repository:

```bash
python3 .devcontainer/local-features/codex/test/test-feature-config.py
bash .devcontainer/local-features/codex/test/test-documentation.sh
```

For live acceptance, connect a fresh desktop chat using the activation steps in
`NOTES.md`. Authorize the parent to create a disposable bare repository and
seed commit, a protected fixture worktree, and separate parent/delegate branches
and linked worktrees. Choose a new acceptance directory outside both seats'
effective writable roots that the configured container user can write when
approved; use no production repository. Record that directory in working notes
outside repositories. Include an ignored `.worktrees/` root in the fixture seed.
The parent prepares the fixture through supported approval, then captures its
refs and worktree registrations with these commands, substituting the bare
repository path for `REPO`:

```bash
git --git-dir="$REPO" show-ref
git --git-dir="$REPO" worktree list --porcelain
```

Give the delegate its own authorized branch/destination and the mounted recovery
procedure's path. Each seat attempts `git worktree add` with its default policy,
reads `~/.agents/instructions/setup-recovery.md` after failure, inspects the
partial refs/registrations/destination, and follows that canonical procedure.
The source branch and intended destination must be recorded before the attempt.
Require each seat to read its own effective permissions and tool schema, rather
than inheriting the parent's policy report. After setup, each performs a write
and Git status in its own worktree, with separate supported approval if the
continuation command also needs it. Record each command's actual status/output;
seeded partial branches must be identified as fixtures rather than failed-attempt
effects.

Acceptance requires a real default sandbox denial and one successful supported
automatic-review setup retry for each seat, subsequent actions in distinct
worktrees, and readback of their written files. Compare the protected fixture's
refs, registration and any ownership-record fixture against the captured
baseline; intentional parent/delegate additions are the only allowed changes.
Prove the preservation comparison rejects a deliberately changed baseline.
Exercise safe setup and ordinary command failure separately; refused approval
and ownership-refusal classification controls must retain their stop outcomes.
Label hypothetical controls as hypothetical. A tool that supplies no independent
reviewer-decision record cannot establish that provenance.

Retain the raw outputs and final comparison in task working notes, and publish
only verified outcomes on the review artifact. A passed input suite alone, a
manually approved retry, or a setup without a captured denial is insufficient.
Keep the disposable worktrees for diagnosis; removal requires the owner's
specific direction. Startup availability also requires the activation procedure
and its reader-proxy dispositions to be verified before the unit is complete.

## Publication

Merging to `main` triggers
[`.github/workflows/publish.yaml`](../../../.github/workflows/publish.yaml),
which builds and pushes `ghcr.io/hube/devcontainer:latest`. Identify the run
created by the merge and wait for it to finish:

```bash
gh run list --workflow publish.yaml --branch main --limit 1
gh run watch <run-id> --exit-status
```

Do not begin post-publication acceptance unless the workflow exits zero. A
failed workflow means the reviewed commit is not known to be present in the
published tag; inspect the run log, fix or rerun the publication job, and wait
for a successful run.

## Post-publication acceptance

Pull the published tag explicitly so a cached pre-merge image cannot satisfy
the consumer test, then exercise the original image-only consumer path:

```bash
docker pull ghcr.io/hube/devcontainer:latest
bash .devcontainer/local-features/codex/test/test-image-consumer.sh ghcr.io/hube/devcontainer:latest
```

Close issue #36 only after both commands exit zero and the consumer test
reports successful post-create health and sandboxed patch persistence. If the
test fails, the problem is in the published-image consumer path; users may
still be unable to start the image or persist Codex patches. Preserve the full
output, correct the publication or runtime failure, publish again, and repeat
this check before closing the issue.

## Cleanup

The runtime and consumer harnesses remove resources they own and fail when
required cleanup does not succeed. Because the stable local image is supplied
by the maintainer, remove it explicitly after acceptance:

```bash
docker image rm -f codex-runtime-test:acceptance
```

If cleanup fails, the command diagnostic identifies the retained build log,
container, volume, or image. Remove that named resource after restoring Docker
or filesystem access; do not assume a failed harness left no resources behind.

## Retiring runtime relaxations

If the default-security control starts passing, stop publication. The current
`seccomp=unconfined` or `apparmor=unconfined` setting may no longer be needed,
so preserving it would retain unnecessary container-wide exposure. Redesign
the outer runtime contract, rerun the controlled matrix, and update the Feature
metadata and user guidance before publishing.
