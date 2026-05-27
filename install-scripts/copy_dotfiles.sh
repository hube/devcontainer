#!/usr/bin/env bash

echo ">Copying dotfiles to the remote user's home directory"

cp -r home/. ~

echo ">Done copying dotfiles"
