# About

This repo provides a [development container][1] Docker image with general
development dependencies so that they can be used across projects and
development machines. The devcontainer in this repo includes:
* Zsh and Oh My Zsh
* Git
* Claude Code, with the `hube-agent` skills cloned and installed on container start

Code is mounted in the `/workspaces` dir. The devcontainer image makes the
`/workspaces` parent directory writable by the configured container user so that
interactive shells can create sibling project directories, such as
`/workspaces/other-repo`.

Configurations that mount a volume over `/workspaces` itself are responsible for
that mount's permissions.

On container start, the `agent-skills` Feature clones
`git@github.com:hube/agent-skills.git` into `/workspaces/agent-skills` if it is
absent, refreshes its remote refs if it is present, and runs the repository's
own idempotent `setup.sh`. Cloning uses the forwarded SSH agent. If the agent
holds no identities the container still starts, and the Feature explains on
stderr that skills will not load until you run `ssh-add` on the host and
restart.

The clone is scratch space. `/workspaces/<project>` is a bind mount of the host
directory you opened, but sibling directories such as `/workspaces/agent-skills`
live on the container filesystem and are destroyed on rebuild. Edit
`agent-skills` from its own workspace, where the repository is bind-mounted from
the host.

Both the remote and the clone path are Feature options, `repo` and `cloneDir`.

This devcontainer can be further customized on a per-project basis by creating a
`.devcontainer` directory in the project directory with a
[devcontainer.json file][4] and adding [Dev Container Features][2]

# Getting started

Install the [Dev Container CLI][3], then run:

```sh
devcontainer up # builds a devcontainer Docker container and then starts it
```

Execute an interactive shell in the container:

```bash
devcontainer exec zsh
```

Stop the container, remove it, and show all containers:

```bash
docker stop <container ID>
docker rm <container ID>
docker ps -a
```

[1]: https://containers.dev
[2]: https://containers.dev/features
[3]: https://containers.dev/implementors/reference
[4]: https://containers.dev/implementors/json_schema
