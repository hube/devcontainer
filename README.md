# About

This repo provides a Docker container containing general development
dependencies so that they do not need to be installed on a physical machine

# Getting started

Build a Docker image tagged `devcontainer-img` from the Dockerfile and
create a container named `<project-name>` from the image. Then show all containers

```bash
docker build -t devcontainer-img .
docker create --name <project-name> -v ../docker-code:/workspace/code devcontainer-img
docker ps -a
```

Start the container, execute an interactive shell

```bash
docker start devcontainer
docker exec -it devcontainer zsh
```

Stop the container, remove it, show all containers

```bash
docker stop devcontainer
docker rm devcontainer
docker ps -a
```

## Configure AWS CLI

https://docs.aws.amazon.com/cli/latest/userguide/getting-started-quickstart.html

```bash
aws login --remote
```

```bash
aws logout
```
