## Behavior

On container start this feature clones the repo if the clone directory is
absent, refreshes its remote refs with `git fetch` if it is already a clone, and
then runs the repo's idempotent `setup.sh`. It never merges, so a working tree is
never moved under an in-flight session.

By default the remote is [`hube/agent-skills`][1] and the clone lands in
`/workspaces/agent-skills`. Both are options, `repo` and `cloneDir`.

Cloning uses the forwarded SSH agent. This feature depends on the `ssh` feature,
whose own `postStartCommand` makes the agent socket writable and seeds
`~/.ssh/known_hosts` — without the latter an SSH clone fails host key
verification. It also depends on `workspaces-permissions`, which makes
`/workspaces` writable by the container user.

## Failure handling

This feature never fails container start. If the SSH agent holds no identities,
if the remote is unreachable, or if `setup.sh` fails, the container comes up
anyway and the reason is written to stderr along with the underlying `git` or
`setup.sh` message.

## Caveats

The clone is scratch space. `/workspaces/<project>` is a bind mount of the host
directory you opened, but sibling directories such as `/workspaces/agent-skills`
live on the container filesystem and are destroyed on rebuild. Edit the skills
repo from its own workspace, where it is bind-mounted from the host.

[1]: https://github.com/hube/agent-skills
