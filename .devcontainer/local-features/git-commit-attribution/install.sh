#!/usr/bin/env bash
set -euo pipefail

SHARE=/usr/local/share/git-commit-attribution
HOOKS="$SHARE/hooks"

# Hook names from githooks(5) of git 2.53 (the image's git). A name added by
# a future git version must be classified absence-equivalent-or-adapter
# before joining this list — see NOTES.md.
HOOK_NAMES=(
  applypatch-msg pre-applypatch post-applypatch
  pre-commit pre-merge-commit prepare-commit-msg commit-msg post-commit
  pre-rebase post-checkout post-merge pre-push
  pre-receive update proc-receive post-receive post-update
  reference-transaction push-to-checkout pre-auto-gc post-rewrite
  sendemail-validate fsmonitor-watchman
  p4-changelist p4-prepare-changelist p4-post-changelist p4-pre-submit
  post-index-change
)

# Node bootstrap: the committed bundle's shebang is /usr/local/bin/node.
NODE_TARGET=/usr/local/share/nvm/current/bin/node
if [[ ! -x "$NODE_TARGET" ]]; then
  echo "git-commit-attribution: $NODE_TARGET is not executable." >&2
  echo "Every commit in the container depends on this interpreter, so the gate cannot install." >&2
  echo "Remedy: ensure ghcr.io/devcontainers/features/node:2 installs before this Feature (dependsOn)." >&2
  exit 1
fi
ln -sfn "$NODE_TARGET" /usr/local/bin/node
[[ -x /usr/local/bin/node ]]

install -d -m 0755 "$SHARE" "$HOOKS"
# Copied verbatim: no substitution touches either artifact (the spec path
# and shebang are compiled in), which is what keeps the committed bundle
# byte-identical to a clean rebuild.
install -m 0755 dispatch.sh "$HOOKS/dispatch"
install -m 0755 dist/validate "$SHARE/validate"

for name in "${HOOK_NAMES[@]}"; do
  ln -sfn "$HOOKS/dispatch" "$HOOKS/$name"
done

# Control setting → system scope at image build (docs/feature-authoring.md:
# silent absence would mean a false belief the gate is active).
git config --file /etc/gitconfig core.hooksPath "$HOOKS"
chmod 0644 /etc/gitconfig

# postStart warning script, owned by the container user.
user_home="/home/${_CONTAINER_USER}"
rsync -rp \
    --chown="${_CONTAINER_USER}:${_CONTAINER_USER}" \
    --chmod=D755,F755 \
    bin "${user_home}"

echo ">git-commit-attribution installed: hooksPath=$HOOKS, spec expected at /etc/devcontainer/feature/git-commit-attribution/trailer-contract"
