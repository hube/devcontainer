#!/usr/bin/env bash

rsync -rp \
    --chown=${_CONTAINER_USER}:${_CONTAINER_USER} \
    --chmod=D755,F755 \
    bin /home/${_CONTAINER_USER}
