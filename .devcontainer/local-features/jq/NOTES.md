# Preserve publication text

The jq compatibility Feature supplies official jq 1.8.2 ahead of the
package-provided binary on PATH. It preserves `/usr/bin/jq`; removing the
Feature does not require repairing the package. The image publication workflow
currently targets Linux ARM64. The Feature also selects the official AMD64
artifact for the repository's existing CI image-build checks; that does not add
an AMD64 published image. Other architectures fail installation rather than
selecting a different executable.

## Activate the corrected image

For repository development, rebuild the image from this repository's
`.devcontainer/devcontainer.json`. Image consumers must pull the image built
from the intended merge and recreate their consumer using that image; restarting
an existing container does not change its installed executable. Select that
publication with the
[maintainer publication procedure](../codex/MAINTAINERS.md#publication).
Preserve user state through the consumer's existing bind mounts and volumes.

In the resulting container, run:

```sh
command -v jq
jq --version
sha256sum /usr/local/bin/jq
/usr/bin/jq --version
```

The effective executable must be `/usr/local/bin/jq`, report `jq-1.8.2`, and
match the ARM64 digest pinned in this Feature's installer. A different path,
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
alone cannot establish intact publication. The maintainer procedure supplies
that comparison and protects the rest of the target artifact. Keep exact body
readback after adoption too.
