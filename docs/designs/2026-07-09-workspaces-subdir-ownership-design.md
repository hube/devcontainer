# Workspaces Subdirectory Ownership Design

Status: Approved for implementation planning

Issue: https://github.com/hube/devcontainer/issues/16

## Summary

The base devcontainer image should let the configured container user create
sibling project directories under `/workspaces`, for example when cloning
another repository from an interactive shell.

Current verified behavior in the running container:

```text
/workspaces              root:root 755, not writable by devcontainer
/workspaces/devcontainer devcontainer:devcontainer 755, writable by devcontainer
```

The fix targets the normal case where `/workspaces` is the image/container
filesystem path. Supporting downstream configurations that mount a volume over
`/workspaces` itself is explicitly out of scope, because that mount hides the
image-layer directory metadata.

## Goals

- Make `/workspaces` writable by the configured non-root container user.
- Preserve the current non-root default user model.
- Avoid recursive ownership changes that could touch mounted repositories or
  volumes.
- Keep the implementation consistent with the repo's existing local Feature
  pattern.

## Non-Goals

- Do not support configurations that mount over `/workspaces`.
- Do not change ownership recursively under `/workspaces`.
- Do not replace the current `ubuntu:rolling` image configuration with a custom
  Dockerfile solely for this behavior.
- Do not hardcode the username as `devcontainer`; follow the configured
  `_CONTAINER_USER`.

## Recommended Approach

Add a small local Dev Container Feature, for example
`.devcontainer/local-features/workspaces`, and include it in
`.devcontainer/devcontainer.json`.

The Feature should declare:

```json
{
  "id": "workspaces",
  "version": "1.0.0",
  "name": "Workspace parent directory ownership",
  "installsAfter": ["ghcr.io/devcontainers/features/common-utils"]
}
```

Its `install.sh` should run as root and validate that `_CONTAINER_USER` names an
existing user before changing directory metadata:

```bash
#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${_CONTAINER_USER:-}" ]] || ! id "${_CONTAINER_USER}" >/dev/null 2>&1; then
  echo "Container user '${_CONTAINER_USER:-}' does not exist" >&2
  exit 1
fi

install -d -o "${_CONTAINER_USER}" -g "${_CONTAINER_USER}" -m 0755 /workspaces
```

Use `install -d` rather than separate `mkdir`, `chown`, and `chmod` calls
because it expresses the intended final directory state in one operation:
directory exists, owner is `_CONTAINER_USER`, group is `_CONTAINER_USER`, and
mode is `0755`.

## Alternatives Considered

### Lifecycle Command

A `postCreateCommand` or similar lifecycle hook could repair `/workspaces`
ownership after container creation. This is less attractive because it runs
later than a Feature, depends on runtime command user semantics, and turns an
image invariant into a startup repair step.

### Custom Dockerfile

A local Dockerfile could create and chown `/workspaces` before Features are
applied. This would work, but it is heavier than necessary and changes the repo
from direct image usage to a custom build path for one directory metadata
change.

## Codebase Impact

Expected implementation changes:

- Add `.devcontainer/local-features/workspaces/devcontainer-feature.json`.
- Add `.devcontainer/local-features/workspaces/install.sh`.
- Add `"./local-features/workspaces": {}` to
  `.devcontainer/devcontainer.json`.
- Update `README.md` to document that the container user can create sibling
  directories under `/workspaces`.

Existing local Features that copy files into `/home/${_CONTAINER_USER}` should
be unaffected.

## Verification

After rebuilding the devcontainer image, verify inside the rebuilt container:

```bash
stat -c '%U:%G %a %n' /workspaces
test -w /workspaces
mkdir /workspaces/test-subdir
rmdir /workspaces/test-subdir
```

Expected result:

```text
devcontainer:devcontainer 755 /workspaces
```

If `${localEnv:USERNAME}` is set to a different valid username during build, the
expected owner and group should match that configured user instead of the
literal `devcontainer` default.

## Risks

- If a downstream container mounts over `/workspaces`, this image-layer fix will
  not apply. That is out of scope and should be documented rather than worked
  around here.
- If `_CONTAINER_USER` is missing or does not exist, the Feature should fail
  clearly during build instead of silently creating a root-owned directory.
- A recursive ownership command would be risky because it could mutate mounted
  repositories or volumes. The implementation must only set metadata on
  `/workspaces` itself.
