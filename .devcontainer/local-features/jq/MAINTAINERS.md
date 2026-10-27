# Accept publication integrity

This Feature owns the official jq artifact, pinned digest and architecture
selection. Repository tests cover these inputs and installation wiring;
acceptance probes exercise the actual built-image executable. Neither workflow
success nor a version string establishes exact text preservation.

## Build and identify the candidate

From this repository's task worktree, run:

```sh
npm ci
npm run typecheck
npm run lint
npm test
npm run build
git diff --exit-code -- \
  .devcontainer/local-features/git-commit-attribution/dist/ \
  .devcontainer/local-features/jq/dist/
```

After publishing the PR head, run `gh pr checks PR_NUMBER --repo hube/devcontainer`
with its actual number. Both `validator` and `local-features` must succeed; the
latter runs the local Feature shell suites, including install-order image builds.
Retain their output and distinguish CI's explicit live-runtime skips from checks
that ran.
For repository development, rebuild this repository's
`.devcontainer/devcontainer.json` with the Dev Containers CLI. Assign an unused
task-owned image tag to `CANDIDATE_IMAGE` before running the build commands
below. The publication workflow
in `.github/workflows/publish.yaml` uses `ubuntu-24.04-arm` without a platform
matrix: its published target is Linux ARM64. Existing CI install-order tests
also build on AMD64; the Feature pins that artifact separately. CI build success
does not establish AMD64 publication or fresh-consumer acceptance.

```sh
devcontainer build --workspace-folder "$PWD" --image-name "$CANDIDATE_IMAGE"
docker image inspect "$CANDIDATE_IMAGE" --format '{{.Id}} {{.Os}}/{{.Architecture}}'
docker run --rm --entrypoint sh "$CANDIDATE_IMAGE" -c \
  'printf "PATH=%s\n" "$PATH"; command -v jq; jq --version;
   sha256sum /usr/local/bin/jq; /usr/bin/jq --version;
   dpkg-query -S /usr/bin/jq'
```

Run the following on the Docker Desktop host with the normal image host-mount
prerequisites in place. This creates a new disposable consuming project from the
named candidate; set `CANDIDATE_IMAGE` to the image just built:

```sh
CONSUMER_WORKSPACE=$(mktemp -d)
mkdir "$CONSUMER_WORKSPACE/.devcontainer"
python3 - "$CONSUMER_WORKSPACE/.devcontainer/devcontainer.json" \
  "$CANDIDATE_IMAGE" <<'PYTHON'
import json
from pathlib import Path
import sys
Path(sys.argv[1]).write_text(json.dumps({
    'image': sys.argv[2], 'appPort': ['127.0.0.1::2222']
}), encoding='utf-8')
PYTHON
cp .devcontainer/local-features/jq/test/acceptance.py \
  "$CONSUMER_WORKSPACE/acceptance.py"
devcontainer up --workspace-folder "$CONSUMER_WORKSPACE" \
  > "$CONSUMER_WORKSPACE/up.json"
devcontainer exec --workspace-folder "$CONSUMER_WORKSPACE" sh -c \
  'printf "PATH=%s\n" "$PATH"; command -v jq; jq --version;
   sha256sum /usr/local/bin/jq; /usr/bin/jq --version'
devcontainer exec --workspace-folder "$CONSUMER_WORKSPACE" \
  python3 acceptance.py /usr/local/bin/jq /tmp/jq-consumer-evidence
```

Retain `up.json`, the image ID/architecture and the output. Before cleanup,
read `containerId` from `up.json` and copy `/tmp/jq-consumer-evidence` out with
`docker cp`. Remove only that disposable container and workspace after retaining
the evidence. Existing consumer mounts or credential volumes are not cleanup
targets. For nested execution, use the existing
`bash .devcontainer/local-features/codex/test/test-image-consumer.sh "$CANDIDATE_IMAGE"`
harness for its daemon-visible workspace translation and fixture cleanup; it
requires the repository worktree itself to be beneath an outer bind visible to
Docker Desktop. If that prerequisite is unavailable, run the host recipe. Run
the exact jq probe separately as below and record which route actually ran.

## Compare exact decoded text

Run the self-contained acceptance probe inside the candidate image, copying the
probe rather than relying on a host bind path visible to the Docker daemon:

```sh
cid=$(docker create --entrypoint python3 "$CANDIDATE_IMAGE" \
  /tmp/acceptance.py /usr/local/bin/jq /tmp/jq-evidence)
docker cp .devcontainer/local-features/jq/test/acceptance.py "$cid:/tmp/acceptance.py"
docker start --attach "$cid"
docker cp "$cid:/tmp/jq-evidence" "$EVIDENCE_DIRECTORY"
docker rm "$cid"
```

Choose an empty task-owned `EVIDENCE_DIRECTORY`. The probe generates its own
multibyte-boundary fixture, representative large Markdown body and small working
control, runs stdin and file inputs, decodes each JSON output and requires exact
text equality. Preserve the generated files and raw output. Separately run the
same probe with a known-affected binary: equality must fail for the affected
fixture while its small control passes. The candidate preserves `/usr/bin/jq`;
read its package/version with the commands above and repeat the container probe
with `/usr/bin/jq` as its binary argument. A passing package binary cannot serve
as the affected control. A self-contained ARM64 control can instead be acquired
from the [official jq 1.8.1 release](https://github.com/jqlang/jq/releases/tag/jq-1.8.1):

```sh
AFFECTED_BINARY=$(mktemp)
curl --fail --location \
  https://github.com/jqlang/jq/releases/download/jq-1.8.1/jq-linux-arm64 \
  --output "$AFFECTED_BINARY"
printf '%s  %s\n' \
  6bc62f25981328edd3cfcfe6fe51b073f2d7e7710d7ef7fcdac28d4e384fc3d4 \
  "$AFFECTED_BINARY" | sha256sum --check -
chmod 755 "$AFFECTED_BINARY"
```

Create a separate probe container with binary argument `/tmp/jq-affected`, copy
`AFFECTED_BINARY` to that path with `docker cp` before starting it, and copy the
same `acceptance.py` as above. Retain its nonzero result, complete output and
fixtures; confirm the small-control lines pass and the boundary lines fail.
A synthetic mutation of JSON proves the comparator fires but
does not substitute for this known-affected-binary control.

## Verify authorized publication

Use an author-owned unit PR comment in `hube/devcontainer`. For an agent-authored
comment, resolve its first-line identity from the active programme's
[identity contract](../../../docs/delivery-programmes/codex-autonomous-recovery-delivery-plan.md#identity-line-format)
and the current role/session inputs. End the body with a fenced metadata block
containing `Harness`, `Harness-Version`, `Model` and `Skills`, in that order;
use actual harness/model/skill values. In Codex, resolve them through the
[Codex attribution procedure](https://github.com/hube/claude-home/blob/main/instructions/committing.md#resolve-codex-attribution-inputs).
For other harnesses, use the attribution producer specified by that harness's
governing instructions.
An unavailable identity input leaves agent publication unauthorized until that
input is restored. Do not overwrite the PR body or unrelated
content. Copy the generated large body into the corrected consumer, add its
identity line and metadata, then serialize the final UTF-8 body with effective
`jq -Rs '{body: .}' body.md > payload.json`. Submit that file using
the following command, substituting the actual PR number:

```sh
gh api --method POST repos/hube/devcontainer/issues/PR_NUMBER/comments \
  --input payload.json
```
For a repeated run, inspect the previously recorded fixture comment you own
and use `--method PATCH repos/hube/devcontainer/issues/comments/COMMENT_ID`
with its actual identifier and the same payload file. Protect other comments.
Read the returned comment's `url` directly with `gh api` into `readback.json`.
Run the [operator comparison](NOTES.md#publish-safely-before-adoption) without
newline translation.

Before trusting the comparator, change one character in a disposable copy of
the expected body and confirm the same assertion fails. Retain the exact
payload/body/readback and comment URL. Supply GitHub authentication through the
existing consumer mechanism; never print tokens or put credentials in evidence.
The affected earlier case is file-backed GitHub body publication and complete
body readback in the Codex Feature's
[autonomous publication acceptance](../codex/MAINTAINERS.md#verify-autonomous-publication).
For this jq input change, record the existing unit PR's title, base, remote head
and body before the fixture comment, then compare those fields afterward:
only the authorized fixture comment may be added or updated. Retain the unit's signed-commit and
remote-ref receipts alongside the corrected-image payload and exact comment
readback. The earlier full parent/delegate recovery matrix remains separate
coverage; this case establishes the JSON publication path affected by jq.

## Retire the compatibility input

When image inputs change, run the preceding acceptance on package-provided jq
in an image built **without** this Feature. Remove the consumer declaration in
a task-owned candidate, rebuild and identify the package executable and PATH;
merely invoking `/usr/bin/jq` in the overlay image does not exercise removal.
Run both fixtures and the working control through stdin and files, authorized
publication with exact authoritative body readback, and fresh consumer adoption
on every supported published image/architecture derived from the then-current
workflow. Preserve image and package identifiers beside the results. Remove the
Feature and its consumer declaration only after all these checks pass; a newer
package version alone does not satisfy retirement. No runtime poller or automatic
self-disable service participates in this procedure.
