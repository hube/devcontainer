#!/usr/bin/env bash

# Edit the `hasCompletedOnboarding` setting in .claude.json to have Claude Code
# skip the authentication dialog and instead read credentials from the existing
# .claude/.credentials.json file
if [ -f ~/.claude/.credentials.json ] && \
   [ -f ~/.claude.json ] && \
   [ "$(jq '.hasCompletedOnboarding == true' ~/.claude.json)" != "true" ]
then
  echo "Found existing Claude Code credentials"
  echo "Configuring Claude Code to skip credentials dialog"

  tmp=$(mktemp)
  jq '.hasCompletedOnboarding = true' ~/.claude.json > "$tmp" && mv "$tmp" ~/.claude.json

  echo "Done configuring Claude Code"
fi
