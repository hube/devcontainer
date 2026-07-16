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
