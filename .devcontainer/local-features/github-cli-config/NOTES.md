# GitHub CLI configuration

This local feature extends the official `github-cli` feature. It does not
install or replace the `gh` binary; it configures persistent GitHub CLI
authentication for the binary supplied by the official feature.

## Runtime bootstrap

`GH_TOKEN` and `GITHUB_TOKEN` are runtime bootstrap inputs supplied through
top-level `remoteEnv`, not feature options or `containerEnv`. Options are
build-time inputs and `containerEnv` would expose tokens to every container
process. On startup, `GH_TOKEN` takes precedence over `GITHUB_TOKEN`, matching
GitHub CLI behavior for github.com. If both values are unset or empty, the
startup hook warns: "Stored GitHub CLI authentication was not updated." It
tells the user to set a host token before restarting the container.

When a token is supplied, the hook unsets `GH_TOKEN` and `GITHUB_TOKEN` for
`gh auth login` before passing the selected token on standard input. This lets
subsequent `gh` processes use stored authentication rather than environment
token authentication.

## Persisted authentication

The feature uses `gh auth login --with-token --insecure-storage`, which stores
authentication as plaintext in `~/.config/gh/hosts.yml`. That directory is
backed by the named Docker volume `github-cli-config-${devcontainerId}`. The
credentials persist until the volume is deleted, or the underlying token
expires, is revoked, or loses required access.

This feature always selects plaintext storage. It does not detect or integrate
with a system credential store. Support for devcontainers that provide a usable
Secret Service or keyring session may be added as a future enhancement. The
named volume keeps stored credentials available to `gh` processes that do not
inherit Dev Container `remoteEnv`, such as SSH-launched processes.

The hook does not remove, log out, switch, delete, or overwrite unrelated
stored accounts. GitHub CLI may create or update the account associated with
the selected token; that is the only stored credential the feature is allowed
to change.

The stored credential serves `gh` subcommands only. The hook does not run
`gh auth setup-git`, so plain `git` commands over HTTPS do not use the stored
credential; this devcontainer relies on SSH agent forwarding for `git` remote
operations instead.

## Removing stored credentials

Once the host stops supplying `GH_TOKEN` and `GITHUB_TOKEN`, a previously
stored token remains in plaintext in the volume until it is removed. Remove it
with `gh auth logout --hostname github.com` inside the container, or delete
the volume with `docker volume rm github-cli-config-<devcontainerId>`.

## Token type guidance

Classic personal access tokens are preferred for `gh auth login --with-token`.
They require all three minimum permissions: `repo`, `read:org`, and `gist`.
Tokens missing any of these permissions cause a non-fatal startup warning.

Fine-grained tokens can work for commands within their granted permissions, but
resource scoping can produce confusing behavior. GitHub CLI recommends setting
`GH_TOKEN` directly instead of passing a fine-grained token to
`gh auth login --with-token`.
