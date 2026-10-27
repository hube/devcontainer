# Preserve publication text

The jq compatibility Feature supplies official jq 1.8.2 ahead of the
package-provided binary on PATH. It preserves `/usr/bin/jq`; removing the
Feature does not require repairing the package. The published image targets
Linux ARM64; unsupported architectures fail installation rather than selecting
a different executable.

## Activate the corrected image

Use the [publication procedure](../codex/MAINTAINERS.md#publication) to select
the intended merge's successful run and obtain its immutable `publication_image`
reference (`ghcr.io/hube/devcontainer@sha256:…`). A moving `latest` tag does not
select an older merge.

Set `CONSUMER_WORKSPACE` to the absolute path of the consuming project. Put the
selected immutable reference in that project's `.devcontainer/devcontainer.json`
`image` field, then run on its Docker Desktop host:

```sh
docker pull "$publication_image"
devcontainer up --workspace-folder "$CONSUMER_WORKSPACE" \
  --remove-existing-container
```

Recreation replaces the selected consumer's container filesystem. Preserve user
state through its existing bind mounts and volumes before running it. Restarting
an existing container does not change its installed executable.

In the resulting container, run:

```sh
command -v jq
jq --version
sha256sum /usr/local/bin/jq
/usr/bin/jq --version
```

The effective executable must be `/usr/local/bin/jq`, report `jq-1.8.2`, and
match the official ARM64 artifact digest below:

```sh
printf '%s  %s\n' \
  8b85c817833814ddca00a144c33705546355afccf0cf39b188f3cdb48b852309 \
  /usr/local/bin/jq | sha256sum --check -
```

This pin identifies `jq-linux-arm64` from the
[official jq 1.8.2 release](https://github.com/jqlang/jq/releases/tag/jq-1.8.2).
A different path,
version or digest means this consumer has not adopted the corrected input;
rebuild or select the intended image and recreate it, then repeat the readback.
These identifiers establish selection; maintainers also run the exact-content
[acceptance procedure](MAINTAINERS.md).

## Publish safely before adoption

Until the corrected image has passed acceptance, serialize publication text
with Python instead of the affected jq raw-slurp path. For an existing UTF-8
`body.md`, create a payload without newline translation:

```sh
python3 - <<'PYTHON'
import json
from pathlib import Path
text = Path('body.md').read_bytes().decode('utf-8')
Path('payload.json').write_text(json.dumps({'body': text}), encoding='utf-8')
PYTHON
```

Publish only to an authorized destination. Read its body back from GitHub's API
and compare decoded text exactly with `body.md`; a successful command status
alone cannot establish intact publication. Compare the decoded `body` field in
`readback.json` with `body.md`:

```sh
python3 - <<'PYTHON'
import json
from pathlib import Path
expected = Path('body.md').read_bytes().decode('utf-8')
actual = json.loads(Path('readback.json').read_bytes())['body']
assert actual == expected, 'authoritative publication body differs'
PYTHON
```

Keep exact body readback after adoption too.
