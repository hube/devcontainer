# Accept publication integrity

This Feature owns the official jq artifact, pinned digest and architecture
selection. Repository tests cover these inputs and installation wiring;
acceptance probes exercise the actual built-image executable. Neither workflow
success nor a version string establishes exact text preservation.

## Build and identify the candidate

Run the repository checks from `package.json` and `.github/workflows/tests.yml`.
Build this repository's `.devcontainer/devcontainer.json` with the Dev Containers
CLI, naming the task-owned candidate image explicitly. The publication workflow
in `.github/workflows/publish.yaml` uses `ubuntu-24.04-arm` without a platform
matrix: its published target is Linux ARM64. Do not infer AMD64 acceptance.

```sh
devcontainer build --workspace-folder "$PWD" --image-name "$CANDIDATE_IMAGE"
docker image inspect "$CANDIDATE_IMAGE" --format '{{.Id}} {{.Os}}/{{.Architecture}}'
docker run --rm --entrypoint sh "$CANDIDATE_IMAGE" -c \
  'printf "PATH=%s\n" "$PATH"; command -v jq; jq --version;
   sha256sum /usr/local/bin/jq; /usr/bin/jq --version;
   dpkg-query -S /usr/bin/jq'
```

Use a fresh disposable consumer of the candidate and repeat the readback with
`devcontainer exec --workspace-folder "$CONSUMER_WORKSPACE"`; this separately
establishes consumer adoption. Existing running containers are not acceptance
of a changed image. Retain the image ID, architecture, artifact/digest, effective
PATH and versions with the results.

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
same probe with a known-affected official jq 1.8.1 binary or a verified affected
package binary: equality must fail for the affected fixture while its small
control passes. A synthetic mutation of JSON proves the comparator fires but
does not substitute for this known-affected-binary control.

## Verify authorized publication

Use an author-owned unit PR comment in `hube/devcontainer`, with the normal
programme identity and metadata. Do not overwrite the PR body or unrelated
content. Copy the generated large body into the corrected consumer, add its
identity line and metadata, then serialize the final UTF-8 body with effective
`jq -Rs '{body: .}' body.md > payload.json`. Submit that file using
the following command, substituting the actual PR number:

```sh
gh api --method POST repos/hube/devcontainer/issues/PR_NUMBER/comments \
  --input payload.json
```
Read the returned comment's `url` directly with `gh api` into `readback.json`.
Compare without newline translation:

```sh
python3 - <<'PYTHON'
import json
from pathlib import Path
expected = Path('body.md').read_bytes().decode('utf-8')
actual = json.loads(Path('readback.json').read_bytes())['body']
assert actual == expected, 'authoritative publication body differs'
PYTHON
```

Before trusting the comparator, change one character in a disposable copy of
the expected body and confirm the same assertion fails. Retain the exact
payload/body/readback and comment URL. Supply GitHub authentication through the
existing consumer mechanism; never print tokens or put credentials in evidence.
Repeat the affected earlier signed, attributed Git/GitHub publication acceptance
through this corrected image, retaining its protected-state comparison and
actual publication readback. A host-side serializer probe is not this acceptance.

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
