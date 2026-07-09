# GitHub CLI Auth Design

Status: Proposed

Issue: https://github.com/hube/devcontainer/issues/19

## Problem

Codex App SSH sessions start the remote Codex app server through SSH using the
remote user's login shell. They do not automatically receive Dev Container
`remoteEnv` values in the same way Dev Container-attached tools do. As a result,
Codex-spawned `gh` commands can miss the GitHub authentication context provided
by `GH_TOKEN`.

At the same time, `GH_TOKEN` should not be baked into the container or forwarded
through Codex command environment policy. `TZ` is non-secret and should be
container-wide.

## Goals

- Make `gh` commands work consistently for Dev Container and Codex App SSH
  sessions.
- Keep GitHub CLI authentication behavior in a local `github-cli` Feature
  because it benefits all container processes, not only Codex.
- Persist GitHub CLI auth across container restarts using a named Docker volume.
- Avoid changing Codex `shell_environment_policy`.
- Move `TZ` to `containerEnv`.
- Keep `GH_TOKEN` as a runtime bootstrap input, not a build-time Feature option.

## Non-Goals

- Do not add a Linux Secret Service or keyring daemon stack to the container.
- Do not store `GH_TOKEN` in Codex config.
- Do not make `GH_TOKEN` a container-wide `containerEnv` value.
- Do not introduce a `codex` wrapper.
- Do not solve non-GitHub secret forwarding for arbitrary tools.

## Design

Replace the direct official GitHub CLI Feature entry with a local
`github-cli` Feature. The local Feature depends on
`ghcr.io/devcontainers/features/github-cli:1`, owns GitHub CLI configuration,
and mounts a named volume at the GitHub CLI config directory:

```json
{
  "type": "volume",
  "source": "github-cli-config-${devcontainerId}",
  "target": "/home/${localEnv:USERNAME:devcontainer}/.config/gh"
}
```

The Feature declares a `postStartCommand` that runs a script installed to a
known user path, following the existing local Feature pattern:

```json
"postStartCommand": "~/bin/devcontainer-feature/github-cli/postStartScript.sh"
```

The post-start script checks whether `gh` is already authenticated for
`github.com` without relying on environment token auth:

```bash
env -u GH_TOKEN -u GITHUB_TOKEN gh auth status --hostname github.com
```

If stored auth is missing and `GH_TOKEN` is set, the script logs in using
plaintext storage in the mounted GitHub CLI config volume:

```bash
printf '%s\n' "${GH_TOKEN}" | env -u GH_TOKEN -u GITHUB_TOKEN gh auth login \
  --hostname github.com \
  --with-token \
  --insecure-storage
```

`GH_TOKEN` remains in top-level `remoteEnv` because Dev Container Features do
not provide an idiomatic runtime secret requirement declaration. Feature
`options` are build/install-time inputs and are not appropriate for tokens.
`containerEnv` would make the token static and visible to all container
processes. `remoteEnv` is the least-broad supported path for a host-provided
runtime secret used by lifecycle hooks.

`TZ` moves from `remoteEnv` to `containerEnv` because it is non-secret,
container-wide configuration.

## Local Feature README

The local `github-cli` Feature must include a README that documents these
constraints:

- `GH_TOKEN` is consumed only as a runtime bootstrap token.
- `GH_TOKEN` must be supplied through top-level `remoteEnv`; Feature options are
  intentionally not used for secrets.
- The Feature stores GitHub CLI auth with `--insecure-storage` in
  `~/.config/gh/hosts.yml`.
- `~/.config/gh` is backed by the `github-cli-config-${devcontainerId}` named
  volume.
- Credentials persist until the Docker volume is deleted or the underlying
  GitHub token expires, is revoked, or loses required access.
- `gh auth login --with-token` is best suited for classic personal access
  tokens. Fine-grained tokens may work for scoped commands but GitHub CLI
  documentation recommends `GH_TOKEN` for fine-grained token usage.
- The script must unset `GH_TOKEN` and `GITHUB_TOKEN` for `gh auth status` and
  `gh auth login`; otherwise environment token auth takes precedence over
  stored credentials.

## Security

This design intentionally chooses plaintext GitHub CLI storage over adding a
Linux Secret Service stack. The current Ubuntu devcontainer does not include
`secret-tool`, `gnome-keyring-daemon`, `dbus-daemon`, or `kwalletd5`. GitHub CLI
uses Linux Secret Service through D-Bus for secure storage, so secure storage
would require additional packages, a running session bus, and an unlocked
keyring.

Plaintext storage is scoped to the configured container user and persisted in a
devcontainer-specific Docker named volume. This is not as strong as a system
credential store, but it avoids broadening `GH_TOKEN` into Codex-spawned command
environments and keeps auth available to all `gh` processes in the container.

## Error Handling

- If `GH_TOKEN` is unset and `gh` already has stored credentials, the script
  exits successfully.
- If `GH_TOKEN` is unset and stored credentials are missing, the script prints a
  warning and exits successfully so container startup is not blocked.
- If `gh auth login` fails because the token is invalid or lacks required
  scopes, the script prints a warning and exits successfully.
- Existing valid stored auth is not overwritten on every container start.

## Verification

Static checks should confirm:

- `.devcontainer/devcontainer.json` references `./local-features/github-cli`
  instead of the direct official GitHub CLI Feature.
- `GH_TOKEN` remains in `remoteEnv`.
- `TZ` is present in `containerEnv` and absent from `remoteEnv`.
- `.devcontainer/local-features/github-cli/devcontainer-feature.json` depends
  on `ghcr.io/devcontainers/features/github-cli:1`.
- The local Feature mounts `github-cli-config-${devcontainerId}` at
  `~/.config/gh`.
- The local Feature declares the post-start script.
- The post-start script unsets `GH_TOKEN` and `GITHUB_TOKEN` for `gh` auth
  checks and login.
- No Codex `shell_environment_policy` change is required.
- The local Feature README documents the constraints listed above.

Runtime checks should include:

- `bash -n` for the post-start script.
- A temporary-home simulation that stubs `gh` and verifies the script checks
  status before login, passes the token on stdin, and does not put the token in
  command-line arguments.
- Rebuilt devcontainer verification when `devcontainer` CLI is available.
