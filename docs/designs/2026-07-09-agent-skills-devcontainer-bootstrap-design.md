# Agent Skills Devcontainer Bootstrap Design

Status: Implemented

Issue: https://github.com/hube/devcontainer/issues/26

Implementation plan: [`docs/implementation-plans/2026-07-09-agent-skills-devcontainer-bootstrap-implementation-plan.md`](../implementation-plans/2026-07-09-agent-skills-devcontainer-bootstrap-implementation-plan.md)

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

Only the first and third matter here. The `.gitignore` step is a no-op inside a devcontainer:
`~/.claude` is a volume, not a git repository, as `git -C ~/.claude rev-parse` confirms. On the host,
where `~/.claude` *is* the `claude-home` repository, `skills/hube-agent` is already ignored by that
repository's own `.gitignore`. Removing the step belongs to `agent-skills`, so this design neither
depends on it nor verifies it.

Verified state in a running container:

```text
/workspaces/agent-skills   on the container overlay filesystem  (lost on rebuild)
~/bin                      container-local                        (lost on rebuild)
~/.claude                  volume claude-code-config-${devcontainerId}
```

Commit `d0005e4` removed the `~/.claude/skills` bind mount from the `claude` local feature. That
bind previously carried the `hube-agent` symlink in from the host. With it gone, `~/.claude/skills`
falls back into the per-project `claude-code-config-${devcontainerId}` volume, and `setup.sh` is the
only thing anywhere that creates the symlink. The removal of that bind and the addition of this
bootstrap are two halves of one change.

## Goals

- Clone `agent-skills` and run its `setup.sh` automatically, on every container start.
- Reach all consumers of the published image without per-repository configuration.
- Never fail container start because the clone could not be created.
- Keep the implementation consistent with the repo's existing local feature pattern.

## Non-Goals

- **Do not restore Codex's `~/.agents/skills`.** `d0005e4` removed the `codex` feature's bind mount
  for the skills directory, and `setup.sh` only ever creates the `~/.claude/skills` symlink, so
  Codex has no `hube-agent` skills after a rebuild. Teaching the installer about Codex's layout
  belongs in `agent-skills`, the repository that owns installation, and should be filed there
  separately. Duplicating that knowledge in this feature would create two places to update.
- Do not solve `/workspaces` ownership. The `workspaces-permissions` feature already makes the
  directory writable by the container user, so the bootstrap needs no `sudo`.
- Do not seed `~/.config/ccstatusline/settings.json`. The `ccstatusline` feature already declares a
  host bind mount for that directory, so it persists across rebuilds on its own.
- Do not update the clone's working tree. The bootstrap never merges.

## Recommended Approach

Add a local feature at `.devcontainer/local-features/agent-skills` that contributes a
`postStartCommand`, mirroring the existing `ssh` feature.

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

`devcontainer-feature.json` declares two options, `repo` and `cloneDir`. Installing the feature is
what enables it, so there is no `enabled` option.

```json
{
  "id": "agent-skills",
  "name": "Agent skills",
  "version": "1.0.0",
  "dependsOn": {
    "./local-features/ssh": {},
    "./local-features/workspaces-permissions": {}
  },
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
`ssh` feature does, then writes the resolved option values to an environment file that the hook
sources. The environment file exists because the specification exposes options to `install.sh` only:

> A supporting tool will parse the `options` object provided by the user. If a value is provided for
> a Feature, it will be emitted to a file named `devcontainer-features.env` [...] This file is
> sourced at build-time for the Feature `install.sh` entrypoint script to handle.

The environment file is sourced explicitly rather than delegated to `direnv`, even though `direnv` is
installed by another local feature. `direnv` is wired as an oh-my-zsh plugin in `~/.zshrc`, so its
hook exists only in interactive zsh sessions; a lifecycle hook runs non-interactively under `/bin/sh`
with `DIRENV_DIR` unset. An `.envrc` would also be refused until someone ran `direnv allow`, because
its trust database lives in a per-project volume and is empty in a fresh container. A plain file that
the hook sources has neither problem.

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

### Feature dependencies and ordering

The feature declares two hard dependencies with `dependsOn`.

`./local-features/ssh` is required because the hook depends on that feature's own `postStartCommand`
having already run, for two reasons: it makes the forwarded SSH agent socket writable, and it seeds
`~/.ssh/known_hosts`, which is container-local and therefore absent on every rebuild. Without the
second, an SSH clone fails host key verification.

`./local-features/workspaces-permissions` is required because the default `cloneDir` is a sibling
directory under `/workspaces`, which that feature makes writable by the container user.

Ordering follows from the dependency. The specification orders lifecycle hooks by feature
installation order:

> For each lifecycle hook (in Feature installation order), each command contributed by a Feature is
> executed in sequence (blocking the next command from executing).

`dependsOn` is preferred over both `installsAfter` and `overrideFeatureInstallOrder`. It is a hard
dependency, so it installs the depended-upon feature rather than merely ordering it if already
present, and a mistyped id fails the build instead of being ignored. All three behaviors were
verified empirically by building throwaway devcontainers with the `@devcontainers/cli`:

| Manifest | Install order | Outcome |
|---|---|---|
| `alpha`, `bravo`, no relationship | `alpha`, `bravo` | Baseline; declaration order is not honored |
| `alpha` `installsAfter` `./local-features/bravo` | `bravo`, `alpha` | Local-path ids do work in `installsAfter` |
| `alpha` `installsAfter` a nonexistent path | `alpha`, `bravo` | **Silently ignored**; build succeeds |
| `alpha` `dependsOn` `./local-features/bravo`, `bravo` unlisted | `bravo`, `alpha` | `bravo` installed anyway, and first |
| `alpha` `dependsOn` a nonexistent path | — | **Build fails** with `ENOENT` |

The built image's `devcontainer.metadata` label reflected the install order in every case, so
lifecycle hook order follows it. `overrideFeatureInstallOrder` is therefore unnecessary.

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

Every warning states the problem, its consequence, and the remedy, in that order. Naming only the
remedy leaves the reader guessing at what went wrong. For an empty agent, for example:

```text
agent-skills: the SSH agent holds no identities, so git@github.com:hube/agent-skills.git
              cannot be cloned. hube-agent skills will not load.
              Run `ssh-add` on the host, then restart the container.
```

`ssh-add -l` distinguishes an empty agent (exit 1) from an unreachable one (exit 2). The remedy is
the same, but the problem is not, so the hook reports which of the two it observed.

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
pieces. It is rejected because dotfiles are meant for user-specific configuration files, whereas this
bootstrap configures how the Claude Code CLI works across every project — a much larger scope than
dotfiles are intended to carry. Dotfiles are also configured client-side, so the behavior would not
be reproducible from this repository.

### Published devcontainer feature

A feature published to a registry would be the most reusable option, and the most machinery. Both
consumers already share this image, so a local feature reaches them just as well.

### Extending the `claude` feature

The `claude` feature already owns the `~/.claude` mounts, so the skills bootstrap could live there.
It is rejected because a separate feature adds to the `claude` feature rather than modifying it,
which keeps both open for extension and closed for modification. It also avoids conflating
installing Claude Code with cloning a repository.

### Named volume for the clone

Mounting a named volume at `cloneDir` would persist the clone across rebuilds. It is rejected
because it would shadow the bind mount when `agent-skills` is itself the workspace, losing the
no-special-case property described above.

## Codebase Impact

- Add `.devcontainer/local-features/agent-skills/devcontainer-feature.json`.
- Add `.devcontainer/local-features/agent-skills/install.sh`.
- Add `.devcontainer/local-features/agent-skills/bin/devcontainer-feature/agent-skills/postStartScript.sh`.
- Add `"./local-features/agent-skills": {}` to `.devcontainer/devcontainer.json`, keeping local
  feature entries in alphabetical order. No `overrideFeatureInstallOrder` entry is needed; the
  feature's own `dependsOn` establishes the order.
- Add `.devcontainer/local-features/agent-skills/NOTES.md` documenting the feature's behavior and
  the ephemeral-clone caveat. `NOTES.md` rather than `README.md`: published features generate their
  `README.md` from `devcontainer-feature.json` and append `NOTES.md` to it, which is why every
  feature in upstream `devcontainers/features` ships both. These local features are never published,
  so only the hand-written half exists.
- Update `README.md` with a one-line pointer to that `NOTES.md`. The top-level README does not carry
  per-feature detail.

In `agent-skills`, update the README's manual install section to describe the automatic bootstrap,
and drop the now-redundant `~/.claude/.gitignore` step from `setup.sh`.

## Verification

Verification splits by whether it can run inside a devcontainer. Both halves were tested against the
current container while writing this design.

### Automatable from inside a devcontainer

The `docker-outside-of-docker` feature supplies a working Docker daemon, and the `@devcontainers/cli`
can be run with `npx`, so `devcontainer build` works in-container. That covers every build-time
assertion:

```bash
npx -y @devcontainers/cli build --workspace-folder . --image-name dc-verify:latest
docker inspect dc-verify:latest \
  --format '{{ index .Config.Labels "devcontainer.metadata" }}'
```

Assert from the label that `./local-features/ssh` and `./local-features/workspaces-permissions`
precede `./local-features/agent-skills`, and that the `agent-skills` entry carries the expected
`postStartCommand`. This is the check that guards the ordering assumption, and it belongs in CI.

### Requires a host

`devcontainer up` does **not** work from inside the container, and the CLI is not the missing piece.
Under `docker-outside-of-docker` the daemon resolves bind mount sources on the host, so the workspace
bind fails:

```text
docker: Error response from daemon: invalid mount config for type "bind":
bind source path does not exist: /host_mnt/private/tmp/.../order-test
```

Anything requiring a started container therefore runs from the host, after a rebuild:

```bash
test -d /workspaces/agent-skills/.git
readlink ~/.claude/skills/hube-agent                    # /workspaces/agent-skills
readlink ~/bin/ccstatusline-worklog-cache-session-cost  # .../bin/ccstatusline-worklog-cache-session-cost
```

Plus the behaviors those commands do not cover: running the hook a second time is a no-op; the start
logs show the `ssh` hook before the `agent-skills` hook; `ssh-add -D` on the host followed by a fresh
`devcontainer up` leaves a running container that warns clearly instead of failing; and a consumer
repository bootstraps with no `.devcontainer` change.

The hook's own branching can be exercised without a full `devcontainer up` by running the script in a
plain `docker run` against the built image, since that needs no workspace bind mount.

## Risks

- Feature ordering is load-bearing and is enforced only by `dependsOn`. The dependency itself fails
  the build when mistyped, but nothing asserts at runtime that the `ssh` hook actually ran first.
  The hook should therefore check its preconditions — a usable agent socket and a `known_hosts`
  entry — and report which one is missing, rather than inferring it from a failed `git clone`. The
  build-time label assertion above guards the ordering in CI. If ordering ever proves unreliable,
  the fallback is `postAttachCommand`: lifecycle phase ordering is absolute, so every feature's
  `postStartCommand` completes before any `postAttachCommand` runs.
- The clone lives on the container overlay filesystem, so uncommitted work in
  `/workspaces/agent-skills` is destroyed on rebuild, in every container whose workspace is not
  `agent-skills` itself. Edit `agent-skills` from its own workspace, where the path is a host bind
  mount. The clone is cheap to recreate, so this is minor here; the general question of which
  `/workspaces` subdirectories persist is tracked in #30.
- Users of the published image other than the repository owner cannot clone the private default
  repository, and will see one warning line on every container start. The `repo` option is the
  escape hatch.
