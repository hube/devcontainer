#!/usr/bin/env bash

## Enable rw permissions on the SSH auth socket
sudo chmod 666 /run/host-services/ssh-auth.sock

## Copy known_hosts to reduce SSH prompts
if [ ! -e ~/.ssh/known_hosts ]
then
  echo "Copying known_hosts from ~/host-readonly/home/.ssh to ~/.ssh"

  mkdir -p ~/.ssh
  cp ~/host-readonly/home/.ssh/known_hosts ~/.ssh/known_hosts
  chmod 600 ~/.ssh/known_hosts
fi
