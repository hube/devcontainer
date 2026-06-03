#!/usr/bin/env bash

## Enable rw permissions on the SSH auth socket
sudo chmod 666 /run/host-services/ssh-auth.sock

## Copy known_hosts to reduce SSH prompts
mkdir -p ~/.ssh
cp ~/.ssh-host/known_hosts ~/.ssh/known_hosts
chmod 600 ~/.ssh/known_hosts
