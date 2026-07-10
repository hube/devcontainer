# GitHub CLI Auth Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Persist GitHub CLI credentials in a devcontainer-specific Docker volume, bootstrapped from runtime GH_TOKEN or GITHUB_TOKEN so all container processes can use stored gh authentication.

**Architecture:** Retain the official github-cli Feature as the gh binary provider. Add a github-cli-config local Feature that depends on it, mounts gh configuration, and installs a non-fatal user post-start hook. The hook prefers GH_TOKEN, otherwise GITHUB_TOKEN, clears both token variables for its gh child process, and persists the selected credential.

**Tech Stack:** Dev Containers local Features, Bash, GitHub CLI, Python 3, Docker, Dev Container CLI.

Design: docs/designs/2026-07-09-github-cli-auth-design.md

## Tasks

### Task 1: Hook and hermetic tests

- Create the local post-start hook and a temporary HOME/PATH stub-gh test. Assert no-token no-op/warning, GITHUB_TOKEN fallback, GH_TOKEN precedence, stdin-only token delivery, both token variables unset for gh, no token in arguments, and non-fatal login failure.
- Implement the hook: choose non-empty GH_TOKEN, otherwise GITHUB_TOKEN; when neither exists warn and exit zero; otherwise pipe the selected token to gh auth login with hostname github.com, with-token, insecure-storage, and both environment token variables removed.
- Run bash -n and the test harness; then review, SSH-sign, commit, and validate required trailers.

### Task 2: Feature packaging and devcontainer wiring

- Add a github-cli-config Feature manifest with the official github-cli dependency, a devcontainer-specific ~/.config/gh volume, and the exact post-start hook path.
- Add an installer that validates _CONTAINER_USER and copies bin into that user's home with executable ownership/modes.
- Add a Python json static test for manifest fields, official dependency, mount, hook, both remoteEnv token values, containerEnv.TZ, absent remoteEnv.TZ, and absent Codex shell_environment_policy.
- Wire the local Feature alphabetically after direnv; retain tokens only in remoteEnv and move TZ to containerEnv. Run syntax/static checks, then commit and validate trailers.
