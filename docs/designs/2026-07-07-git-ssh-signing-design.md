# Git SSH Signing Feature Design

Status: Draft

## Context

The `hube/devcontainer-dotfiles` repository currently carries Git SSH signing
configuration and signing-related SSH files. Some of that configuration is
generic devcontainer behavior rather than personal dotfile state:

- Git should use SSH as the signing format.
- Commit and tag signing should be enabled when signing support is requested.
- Git should read an allowed signers file from the user's SSH directory.
- Git should use the user's SSH public key as the signing key.

The personal identity remains dotfile-specific:

- Git user name.
- Git user email.
- The actual signing public key.
- The actual allowed signers content.

## Goal

Add reusable Git SSH signing plumbing to `hube/devcontainer` so
`hube/devcontainer-dotfiles` can stop hardcoding generic signing configuration.
The feature itself is the opt-in. If a project includes the feature, Git SSH
signing is requested for that devcontainer.

## Non-Goals

- Do not move Git user identity into `hube/devcontainer`.
- Do not track personal signing keys or allowed signers in `hube/devcontainer`.
- Do not add feature options for alternate paths in the first version.
- Do not make the existing SSH feature responsible for Git signing policy.

## Proposed Feature

Create a new local feature:

```json
"./local-features/git-ssh-signing": {}
```

This feature is separate from `./local-features/ssh` because SSH connectivity
and Git signing policy are different concerns. The existing SSH feature should
continue to own the SSH agent socket, `known_hosts`, and general SSH setup. The
new feature should own only Git SSH signing configuration.

The feature has no options. Adding the feature means signing should be enabled.
This keeps the first version small and avoids speculative path flexibility.

## Mount Convention

The feature mounts the expected host files into conventional container paths:

| Host path | Container path |
| --- | --- |
| `${localEnv:HOME}/.ssh/id_ed25519.pub` | `/home/${localEnv:USERNAME:devcontainer}/.ssh/id_ed25519.pub` |
| `${localEnv:HOME}/.ssh/allowed_signers` | `/home/${localEnv:USERNAME:devcontainer}/.ssh/allowed_signers` |

Both mounts should be readonly bind mounts.

The feature intentionally uses conventional paths instead of options. If a real
need for alternate host or container paths appears later, options can be added
with that concrete use case in hand.

## Generated Git Configuration

The feature installs a reusable Git include file for the container user:

```ini
[commit]
        gpgSign = true
[tag]
        gpgsign = true
[gpg]
        format = ssh
[gpg "ssh"]
        allowedSignersFile = ~/.ssh/allowed_signers
[user]
        signingKey = ~/.ssh/id_ed25519.pub
```

The recommended include path is:

```text
~/.config/git/ssh-signing.inc
```

The feature should add this file to the user's global Git configuration only
after the expected mounted files are present. This avoids enabling
`commit.gpgSign` when signing cannot work.

## Runtime Validation

Feature installation happens during image build, before host bind mounts are
available. Because of that, `install.sh` cannot reliably validate whether the
host has the signing key and allowed signers file.

Instead, the feature installs a `postStartCommand` script, for example:

```text
~/bin/devcontainer-feature/git-ssh-signing/postStartScript.sh
```

On container start, the script checks:

- `~/.ssh/id_ed25519.pub`
- `~/.ssh/allowed_signers`

If both files exist, the script writes the Git include file and ensures the
user's global `~/.gitconfig` includes it.

If either file is missing, the script prints a clear warning and does not enable
the include:

```text
Git SSH signing was requested, but required files are missing:
  missing: ~/.ssh/allowed_signers

Expected host files:
  ~/.ssh/id_ed25519.pub
  ~/.ssh/allowed_signers

Git SSH signing was not enabled for this container.
```

This avoids silent failure and avoids turning every `git commit` into a signing
error when the host setup is incomplete.

## Idempotency

The post-start script should be safe to run repeatedly.

- Rewriting `~/.config/git/ssh-signing.inc` with the same content is acceptable.
- The include entry in `~/.gitconfig` should not be duplicated.
- Missing-file warnings are acceptable on every start until the host files are
  created.

## Dotfiles Impact

After this feature exists, `hube/devcontainer-dotfiles` can remove generic
signing configuration:

```ini
[commit]
        gpgSign = true
[tag]
        gpgsign = true
[gpg]
        format = ssh
[gpg "ssh"]
        allowedSignersFile = ~/.ssh/allowed_signers
```

The dotfiles repository should keep personal Git identity:

```ini
[user]
        name = Hubert Lee 🤖
        email = hube@users.noreply.github.com
```

The tracked `~/.ssh/id_ed25519.pub` and `~/.ssh/allowed_signers` files can be
removed from dotfiles once the host provides them at the conventional mount
locations.

## Testing

Implementation should verify:

- The feature mounts the expected host files readonly.
- The post-start script enables the Git include when both mounted files exist.
- The post-start script warns and skips enabling the include when either file is
  missing.
- Running the post-start script multiple times does not duplicate the include.
- Existing SSH feature behavior remains unchanged.
