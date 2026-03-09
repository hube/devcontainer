# About

This repo provides a Docker container containing general development
dependencies so that they do not need to be installed on a physical machine

# Getting started

Build a Docker image tagged `dev-machine-img` from the Dockerfile and
create a container named `dev-machine` from the image. Then show all containers

```bash
docker build -t dev-machine-img .
docker create --name dev-machine -v ../docker-code:/root/code dev-machine-img
docker ps -a
```

Start the container, execute an interactive bash shell

```bash
docker start dev-machine
docker exec -it dev-machine bash
```

Stop the container, remove it, show all containers

```bash
docker stop dev-machine
docker rm dev-machine
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
