# About

This repo provides a [development container][1] Docker image with general
development dependencies so that they can be used across projects and
development machines. The devcontainer in this repo includes:
* Zsh and Oh My Zsh
* Git
* Claude Code

Code is mounted in the `/workspaces` dir. The devcontainer image makes the
`/workspaces` parent directory writable by the configured container user so that
interactive shells can create sibling project directories, such as
`/workspaces/other-repo`.

Configurations that mount a volume over `/workspaces` itself are responsible for
that mount's permissions.

The [`agent-skills`](.devcontainer/local-features/agent-skills/NOTES.md) local
feature clones a repo that provides skills for AI agents to use, and installs
them on container start.

The [`github-cli-config`](.devcontainer/local-features/github-cli-config/README.md)
local Feature persists `gh` authentication for processes that do not inherit
Dev Container `remoteEnv`.

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
