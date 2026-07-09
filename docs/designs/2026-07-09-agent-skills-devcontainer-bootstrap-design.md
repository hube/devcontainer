# Agent Skills Devcontainer Bootstrap Design

Status: Designed

Issue: https://github.com/hube/devcontainer/issues/26

## Summary

`hube-agent` skills load from a clone of the private `agent-skills` repository via symlinks that
the repository's own `setup.sh` creates. Nothing recreates that clone after a container rebuild, so
a rebuilt container has no `hube-agent` skills and a broken ccstatusline widget path.

The base image should clone the repository and run its installer automatically on container start,
so that every project using `ghcr.io/hube/devcontainer:latest` comes up with skills loaded and no
manual step.

## Background

`setup.sh` in `agent-skills` is idempotent and performs three actions:

- creates `~/.claude/skills/hube-agent`, symlinked to the clone
- appends `skills/hube-agent` to `~/.claude/.gitignore`
- creates `~/bin/ccstatusline-worklog-cache-session-cost`, symlinked into the clone's `bin/`

Verified state in a running container:

```text
/workspaces/agent-skills   on the container overlay filesystem  (lost on rebuild)
~/bin                      container-local                        (lost on rebuild)
~/.claude                  volume claude-code-config-${devcontainerId}
```

Commit `d0005e4` removed the `~/.claude/skills` bind mount from the `claude` local Feature. That
bind previously carried the `hube-agent` symlink in from the host. With it gone, `~/.claude/skills`
falls back into the per-project `claude-code-config-${devcontainerId}` volume, and `setup.sh` is the
only thing anywhere that creates the symlink. The removal of that bind and the addition of this
bootstrap are two halves of one change.

## Goals

- Clone `agent-skills` and run its `setup.sh` automatically, on every container start.
- Reach all consumers of the published image without per-repository configuration.
- Never fail container start because the clone could not be created.
- Keep the implementation consistent with the repo's existing local Feature pattern.

## Non-Goals

- **Do not restore Codex's `~/.agents/skills`.** `d0005e4` removed the `codex` Feature's bind mount
  for the skills directory, and `setup.sh` only ever creates the `~/.claude/skills` symlink, so
  Codex has no `hube-agent` skills after a rebuild. Teaching the installer about Codex's layout
  belongs in `agent-skills`, the repository that owns installation, and should be filed there
  separately. Duplicating that knowledge in this Feature would create two places to update.
- Do not solve `/workspaces` ownership. The `workspaces-permissions` Feature already makes the
  directory writable by the container user, so the bootstrap needs no `sudo`.
- Do not seed `~/.config/ccstatusline/settings.json`. The `ccstatusline` Feature already declares a
  host bind mount for that directory, so it persists across rebuilds on its own.
- Do not update the clone's working tree. The bootstrap never merges.

## Recommended Approach

Add a local Feature at `.devcontainer/local-features/agent-skills` that contributes a
`postStartCommand`, mirroring the existing `ssh` Feature.

Feature-contributed lifecycle hooks are baked into the published image's `devcontainer.metadata`
label. Both current consumers are bare `{"image": "ghcr.io/hube/devcontainer:latest"}`
configurations, so they inherit the bootstrap with no change of their own.

### Components

```text
.devcontainer/local-features/agent-skills/
  devcontainer-feature.json                                 options; declares postStartCommand
  install.sh                                                rsync bin/ into home; persist options
  bin/devcontainer-feature/agent-skills/postStartScript.sh  clone, fetch, run setup.sh
```

`devcontainer-feature.json` declares two options, `repo` and `cloneDir`. Installing the Feature is
what enables it, so there is no `enabled` option.

```json
{
  "id": "agent-skills",
  "name": "Agent skills",
  "version": "1.0.0",
  "installsAfter": ["ghcr.io/devcontainers/features/common-utils"],
  "options": {
    "repo": {
      "type": "string",
      "description": "Git remote to clone",
      "default": "git@github.com:hube/agent-skills.git"
    },
    "cloneDir": {
      "type": "string",
      "description": "Absolute path the repo is cloned to",
      "default": "/workspaces/agent-skills"
    }
  },
  "postStartCommand": "~/bin/devcontainer-feature/agent-skills/postStartScript.sh"
}
```

`install.sh` runs at build time as root. It copies `bin/` into the container user's home the way the
`ssh` Feature does, then writes the resolved option values to an environment file that the hook
sources. The environment file exists because the specification exposes options to `install.sh` only:

> A supporting tool will parse the `options` object provided by the user. If a value is provided for
> a Feature, it will be emitted to a file named `devcontainer-features.env` [...] This file is
> sourced at build-time for the feature `install.sh` entrypoint script to handle.

`postStartScript.sh` runs at start time as the container user. It sources the environment file, then
clones if the clone is absent, fetches if it is present, and runs `setup.sh`.

### Data flow

```text
ssh postStartScript.sh          chmod 666 ssh-auth.sock; seed ~/.ssh/known_hosts
        |  (must run first)
        v
agent-skills postStartScript.sh
        |-- cloneDir/.git exists?  -- yes --> git fetch --quiet  (never merges)
        |                          -- no  --> ssh-add -l gate, then git clone
        v
        bash cloneDir/setup.sh
```

### Feature ordering

The hook depends on the `ssh` Feature's own `postStartCommand` having already run, for two reasons.
It makes the forwarded SSH agent socket writable, and it seeds `~/.ssh/known_hosts`, which is
container-local and therefore absent on every rebuild. Without the second, an SSH clone fails host
key verification.

The specification orders lifecycle hooks by Feature installation order:

> For each lifecycle hook (in Feature installation order), each command contributed by a Feature is
> executed in sequence (blocking the next command from executing).

Pin that order explicitly with `overrideFeatureInstallOrder` in `.devcontainer/devcontainer.json`
rather than relying on `installsAfter`, which is only a soft dependency and is not documented to
match local-path Feature ids.

### Clone authentication

Clone over SSH, so that the clone's remote and identity match a clone made by hand. `GH_TOKEN` is
present in the container, but it authenticates as `hube-ai`, so an HTTPS clone would leave a
bot-owned remote and HTTPS remote URL.

The consequence is the ordering dependency above, and a dependency on the host SSH agent holding an
identity. When it does not, the hook warns and skips rather than failing.

### Update policy

Clone if absent; otherwise `git fetch` only. Fetching refreshes remote refs so that being behind is
visible, while the working tree never moves under an in-flight session, and a dirty or diverged tree
is never a failure.

This also means opening the `agent-skills` repository itself needs no special case. Its devcontainer
bind-mounts the repository at `/workspaces/agent-skills`, so the hook finds a `.git`, skips the
clone, and runs `setup.sh` against the live working tree.

## Error Handling

Build-time misconfiguration should fail loudly; runtime unavailability should not.

`install.sh` validates `repo`, `cloneDir` (non-empty and absolute), and that `_CONTAINER_USER` names
an existing user. It checks all of them and reports every problem before exiting non-zero. A bad
option value is a build defect and should stop the build.

`postStartScript.sh` never fails container start. Every recoverable condition warns to stderr and
exits 0.

| Condition | Behavior |
|---|---|
| `cloneDir/.git` present | `git fetch --quiet`; on failure warn and continue to `setup.sh` |
| `cloneDir` absent or empty | gate on `ssh-add -l`, then clone |
| `cloneDir` non-empty without `.git` | warn and skip; do not clone over it, do not run `setup.sh` |
| `ssh-add -l` exits 1 or 2 | warn that `ssh-add` must run on the host, then exit 0 |
| clone fails | warn and exit 0; `git` removes its own partial clone |
| `setup.sh` missing or failing | warn and exit 0 |

`ssh-add -l` distinguishes an empty agent (exit 1) from an unreachable one (exit 2), but both need
the same action from the user, so the hook treats them identically.

Exiting 0 also protects the publish workflow. The image is built in GitHub Actions, which has no SSH
agent, so a hard failure in the hook could break image publishing if the build ever executes it.

The `claude-code-config-${devcontainerId}` volume outlives rebuilds, so a stale
`~/.claude/skills/hube-agent` symlink can survive while the clone is gone. The hook normally
re-clones and heals it before Claude Code starts. On the warn-and-skip path the container comes up
with a dangling symlink instead, so the hook should detect that case and warn that skills will not
load. It must not delete the symlink, which is user state.

## Alternatives Considered

### Per-repository lifecycle command

A `postCreateCommand` in each consumer's `.devcontainer/devcontainer.json` would work, but every
consumer would carry a copy of the same bootstrap.

### Dotfiles bootstrap

A dotfiles repository runs automatically in every container and suits the `~/bin` and `~/.config`
pieces. It is rejected because dotfiles are configured client-side, so the behavior would not be
reproducible from this repository.

### Published devcontainer Feature

A Feature published to a registry would be the most reusable option, and the most machinery. Both
consumers already share this image, so a local Feature reaches them just as well.

### Extending the `claude` Feature

The `claude` Feature already owns the `~/.claude` mounts, so the skills bootstrap could live there.
It is rejected because it conflates installing Claude Code with cloning a repository.

### Named volume for the clone

Mounting a named volume at `cloneDir` would persist the clone across rebuilds. It is rejected
because it would shadow the bind mount when `agent-skills` is itself the workspace, losing the
no-special-case property described above.

## Codebase Impact

- Add `.devcontainer/local-features/agent-skills/devcontainer-feature.json`.
- Add `.devcontainer/local-features/agent-skills/install.sh`.
- Add `.devcontainer/local-features/agent-skills/bin/devcontainer-feature/agent-skills/postStartScript.sh`.
- Add `"./local-features/agent-skills": {}` to `.devcontainer/devcontainer.json`, keeping local
  Feature entries in alphabetical order, and add `overrideFeatureInstallOrder` placing
  `./local-features/ssh` before `./local-features/agent-skills`.
- Update `README.md` to document the bootstrap and the caveat below.

In `agent-skills`, update the README's manual install section to describe the automatic bootstrap.

## Verification

After rebuilding the image and starting a fresh container:

```bash
test -d /workspaces/agent-skills/.git
readlink ~/.claude/skills/hube-agent                    # /workspaces/agent-skills
readlink ~/bin/ccstatusline-worklog-cache-session-cost  # .../bin/ccstatusline-worklog-cache-session-cost
grep -qxF 'skills/hube-agent' ~/.claude/.gitignore
```

Then confirm the behaviors the commands above do not cover:

- Running the hook a second time is a no-op.
- The start logs show the `ssh` hook running before the `agent-skills` hook.
- `ssh-add -D` on the host, followed by a fresh `devcontainer up`, leaves a running container that
  warns clearly instead of failing.
- The published image's `devcontainer.metadata` label contains the new `postStartCommand`, and
  `devcontainer up` in a consumer repository bootstraps with no `.devcontainer` change.

## Risks

- `overrideFeatureInstallOrder` is not documented to accept local-path Feature ids. This is the
  one unverified assumption in the design and must be tested rather than assumed. If it does not
  hold, move the hook to `postAttachCommand`: lifecycle phase ordering is absolute, so every
  Feature's `postStartCommand` completes before any `postAttachCommand` runs, which guarantees the
  socket and `known_hosts` are ready regardless of Feature order.
- The clone lives on the container overlay filesystem, so uncommitted work in
  `/workspaces/agent-skills` is destroyed on rebuild, in every container whose workspace is not
  `agent-skills` itself. Edit `agent-skills` from its own workspace, where the path is a host bind
  mount. This predates the design, but automation makes it easier to forget, so `README.md` should
  say so.
- Users of the published image other than the repository owner cannot clone the private default
  repository, and will see one warning line on every container start. The `repo` option is the
  escape hatch.
