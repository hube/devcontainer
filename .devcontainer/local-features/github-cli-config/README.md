# GitHub CLI configuration

This local Feature extends the official `github-cli` Feature. It does not
install or replace the `gh` binary; it configures persistent GitHub CLI
authentication for the binary supplied by the official Feature.

## Runtime bootstrap

`GH_TOKEN` and `GITHUB_TOKEN` are runtime bootstrap inputs supplied through
top-level `remoteEnv`, not Feature options or `containerEnv`. Feature options
are build-time inputs and `containerEnv` would expose tokens to every container
process. On startup, `GH_TOKEN` takes precedence over `GITHUB_TOKEN`, matching
GitHub CLI behavior for github.com. If both values are unset or empty, the
startup hook prints a warning and makes no GitHub CLI auth changes.

When a token is supplied, the hook unsets `GH_TOKEN` and `GITHUB_TOKEN` for
`gh auth login` before passing the selected token on standard input. This lets
subsequent `gh` processes use stored authentication rather than environment
token authentication.

## Persisted authentication

The Feature uses `gh auth login --with-token --insecure-storage`, which stores
authentication as plaintext in `~/.config/gh/hosts.yml`. That directory is
backed by the named Docker volume `github-cli-config-${devcontainerId}`. The
credentials persist until the volume is deleted, or the underlying token
expires, is revoked, or loses required access.

Plaintext storage is intentional: this Ubuntu devcontainer lacks a usable
Secret Service/keyring session. Adding one would require extra packages, a
running D-Bus session, and an unlocked keyring. The named volume keeps the
stored credentials available to `gh` processes that do not inherit Dev
Container `remoteEnv`, such as SSH-launched processes.

The hook does not remove, log out, switch, delete, or overwrite unrelated
stored accounts. GitHub CLI may create or update the account associated with
the selected token; that is the only stored credential the Feature is allowed
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

`gh auth login --with-token` is best suited to classic personal access tokens.
Fine-grained tokens can work for commands within their granted scopes, but
GitHub CLI recommends `GH_TOKEN` for fine-grained token usage.

`gh auth login --with-token` also rejects classic tokens that lack the GitHub
CLI minimum scopes (currently `repo` and `read:org`). Such tokens surface as a
non-fatal `gh auth login failed` warning during container startup.
