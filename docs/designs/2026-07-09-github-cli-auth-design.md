# GitHub CLI Auth Design

Status: Implemented

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

- Make `gh` commands work consistently for all container processes, including
  Dev Container and Codex App SSH sessions.
- Keep GitHub CLI authentication behavior in a local `github-cli-config`
  Feature because it extends the official `github-cli` Feature with
  repo-specific auth persistence.
- Persist GitHub CLI auth across container restarts using a named Docker volume.
- Avoid changing Codex `shell_environment_policy`.
- Move `TZ` to `containerEnv`.
- Keep `GH_TOKEN` and `GITHUB_TOKEN` as runtime bootstrap inputs, not build-time Feature options.

## Non-Goals

- Do not add a Linux Secret Service or keyring daemon stack to the container.
- Do not store `GH_TOKEN` or `GITHUB_TOKEN` in Codex config.
- Do not make `GH_TOKEN` or `GITHUB_TOKEN` container-wide `containerEnv` values.
- Do not introduce a `codex` wrapper.
- Do not solve non-GitHub secret forwarding for arbitrary tools.

## Design

Keep the existing official GitHub CLI Feature entry and add a separate local
`github-cli-config` Feature. The devcontainer depends on both features:

```json
"ghcr.io/devcontainers/features/github-cli:1": {},
"./local-features/github-cli-config": {}
```

The local Feature extends the installed GitHub CLI with configuration,
persistent auth storage, and startup-time auth bootstrapping. It does not
replace or wrap the official GitHub CLI Feature. The local Feature declares the
official GitHub CLI Feature as a dependency because its post-start script
requires the `gh` command:

```json
"dependsOn": {
  "ghcr.io/devcontainers/features/github-cli:1": {}
}
```

The local Feature mounts a named volume at the GitHub CLI config directory:

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
"postStartCommand": "~/bin/devcontainer-feature/github-cli-config/postStartScript.sh"
```

The post-start script treats the GitHub CLI token environment variables as the
only trigger for GitHub CLI auth changes. It selects `GH_TOKEN` when set,
otherwise falls back to `GITHUB_TOKEN`, matching `gh` precedence for github.com.
If neither token is set, the script prints a warning that no GitHub CLI auth
changes are being made and exits successfully. It must not run `gh auth status`,
`gh auth login`, `gh auth logout`, delete `hosts.yml`, or otherwise inspect or
mutate existing stored credentials in this path. Existing `gh` credentials
remain available for later `gh` commands to use naturally.

If either token is set, the script always attempts to add the selected token to
GitHub CLI's stored credentials using plaintext storage in the mounted GitHub
CLI config volume, regardless of whether other credentials already exist:

```bash
printf '%s\n' "${selected_token}" | env -u GH_TOKEN -u GITHUB_TOKEN gh auth login \
  --hostname github.com \
  --with-token \
  --insecure-storage
```

`GH_TOKEN` and `GITHUB_TOKEN` remain in top-level `remoteEnv` because Dev
Container Features do not provide an idiomatic runtime secret requirement
declaration. Feature `options` are build/install-time inputs and are not
appropriate for tokens. `containerEnv` would make tokens static and visible to
all container processes. `remoteEnv` is the least-broad supported path for
host-provided runtime secrets used by lifecycle hooks.

`TZ` moves from `remoteEnv` to `containerEnv` because it is non-secret,
container-wide configuration.

## Local Feature README

The local `github-cli-config` Feature must include a README that documents these
constraints:

- `GH_TOKEN` and `GITHUB_TOKEN` are consumed only as runtime bootstrap tokens.
- `GH_TOKEN` takes precedence over `GITHUB_TOKEN` when both are set, matching
  GitHub CLI behavior for github.com.
- Tokens must be supplied through top-level `remoteEnv`; Feature options are
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
- `gh auth login --with-token` rejects classic tokens missing GitHub CLI's
  minimum scopes (currently `repo` and `read:org`); such tokens surface as a
  non-fatal startup warning.
- The stored credential serves `gh` subcommands only. The script does not run
  `gh auth setup-git`, so `git` over HTTPS does not use the stored credential;
  the devcontainer relies on SSH agent forwarding for `git` remote operations.
- How to remove a stale stored credential: `gh auth logout` inside the
  container, or delete the `github-cli-config-${devcontainerId}` volume.
- If both `GH_TOKEN` and `GITHUB_TOKEN` are unset or empty, the script warns and
  makes no GitHub CLI auth changes.
- If either token is set, the script attempts to store the selected token with
  `gh auth login --with-token --insecure-storage` even when other credentials
  already exist.
- The script must unset `GH_TOKEN` and `GITHUB_TOKEN` for `gh auth login`;
  otherwise environment token auth can take precedence over stored credentials.
- The Feature extends the official `github-cli` Feature and intentionally does
  not install or replace the `gh` binary itself.
- The Feature must not remove, log out, overwrite unrelated accounts, delete
  `hosts.yml`, or call `gh auth switch`.
- GitHub CLI may create or update the account associated with the selected
  token; that account is the only stored credential the Feature is allowed to
  change.

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

A stored token outlives the host's decision to stop supplying it: once
`GH_TOKEN`/`GITHUB_TOKEN` are no longer set, the previously stored credential
remains in the volume until it expires, is revoked, or is removed with
`gh auth logout` or by deleting the volume. The README must document this
remediation path.

## Error Handling

- If both `GH_TOKEN` and `GITHUB_TOKEN` are unset or empty, the script prints a
  warning that no GitHub CLI auth changes are being made and exits
  successfully.
- If `GH_TOKEN` is set, the script selects it.
- If `GH_TOKEN` is unset or empty and `GITHUB_TOKEN` is set, the script selects
  `GITHUB_TOKEN`.
- If a token is selected, the script attempts to store it with `gh auth login
  --with-token --insecure-storage`.
- If `gh auth login` fails because the token is invalid, lacks required scopes
  (including classic tokens below GitHub CLI's minimum scopes), or cannot be
  stored, the script prints a warning and exits successfully. `gh`'s own stderr
  passes through to the postStart log so the underlying cause is visible.
- If `gh` is not on `PATH`, the pipeline fails the same way: the script prints
  a warning and exits successfully.
- The script must not remove or change other existing stored credentials.
- The script must not call `gh auth switch`; any active-account side effects are
  limited to GitHub CLI behavior while storing the selected-token account.

## Verification

Static checks should confirm:

- `.devcontainer/devcontainer.json` references both
  `ghcr.io/devcontainers/features/github-cli:1` and
  `./local-features/github-cli-config`.
- `GH_TOKEN` and `GITHUB_TOKEN` remain in `remoteEnv`.
- `TZ` is present in `containerEnv` and absent from `remoteEnv`.
- `.devcontainer/local-features/github-cli-config/devcontainer-feature.json`
  declares `ghcr.io/devcontainers/features/github-cli:1` in `dependsOn`.
- The local Feature mounts `github-cli-config-${devcontainerId}` at
  `~/.config/gh`.
- The local Feature declares the post-start script.
- The post-start script warns and performs no GitHub CLI auth mutation when
  both `GH_TOKEN` and `GITHUB_TOKEN` are unset or empty.
- The post-start script unsets `GH_TOKEN` and `GITHUB_TOKEN` for `gh auth login`.
- The post-start script selects `GH_TOKEN` over `GITHUB_TOKEN` when both are
  present.
- The post-start script attempts to store the selected token even when other
  credentials already exist.
- The post-start script does not remove, log out, switch, or overwrite unrelated
  stored credentials.
- No Codex `shell_environment_policy` change is required.
- The local Feature README documents the constraints listed above.

Runtime checks should include:

- `bash -n` for the post-start script.
- A temporary-home simulation that stubs `gh` and verifies the script warns and
  does not invoke `gh` when both token variables are unset, selects `GH_TOKEN`
  over `GITHUB_TOKEN`, passes the selected token on stdin, and does not put the
  token in command-line arguments.
- Rebuilt devcontainer verification when `devcontainer` CLI is available.
