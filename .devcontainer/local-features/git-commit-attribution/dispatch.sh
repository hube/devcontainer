#!/bin/sh
# Dispatcher for the git-commit-attribution gate. A container-wide
# core.hooksPath replaces the hook directory for EVERY hook git knows, so
# this script is symlinked under every githooks(5) name and chains to the
# repository's own hook. See NOTES.md for the classification rule new hook
# names must pass before joining the symlink farm.
set -u

# Test seams only; both default to the installed locations.
GCA_ROOT="${GCA_ROOT:-/usr/local/share/git-commit-attribution}"
GCA_NODE="${GCA_NODE:-/usr/local/bin/node}"

hook_name=$(basename "$0")

# --git-common-dir ignores core.hooksPath (the recursion guard) and, from a
# linked worktree where .git is a file, resolves the main repository's .git,
# where hooks actually live. Outside a repository (e.g. reference-transaction
# fires mid-`git init`, before the repository is recognized) rev-parse fails;
# there is no repo hook to chain in that case, so the failure is swallowed
# here rather than left to leak to the user's stderr, and repo_hook is set
# empty (both -x and -f test false on "", even under set -u).
if common_dir="$(git rev-parse --git-common-dir 2>/dev/null)"; then
  repo_hook="$common_dir/hooks/$hook_name"
else
  repo_hook=""
fi

if [ "$hook_name" = "commit-msg" ]; then
  # The repo's own commit-msg hook runs FIRST, before validation: git permits
  # such a hook to rewrite the message file in place, so validating first
  # would let a repo hook silently strip or reorder the required trailers
  # after the only validation pass. Running the repo hook first (and, on
  # success, validating the file it leaves behind) means the validator always
  # judges the message git will actually use. Control must return here rather
  # than exec'ing, since validation still has to run afterward.
  if [ -x "$repo_hook" ]; then
    "$repo_hook" "$@" || exit $?
  elif [ -f "$repo_hook" ]; then
    echo "git-commit-attribution: hook '$repo_hook' exists but is not executable; ignoring it." >&2
  fi

  validator="$GCA_ROOT/validate"
  if [ -x "$validator" ] && [ -x "$GCA_NODE" ]; then
    "$validator" commit-msg "$1" || exit $?
    exit 0
  else
    echo "git-commit-attribution: cannot execute the validator at $validator (interpreter: $GCA_NODE)." >&2
    echo "The commit was not created: the gate fails closed when it cannot run." >&2
    echo "Remedy: rebuild the container; to bypass once, use git commit --no-verify." >&2
    exit 1
  fi
fi

if [ -x "$repo_hook" ]; then
  exec "$repo_hook" "$@"
fi

if [ -f "$repo_hook" ]; then
  echo "git-commit-attribution: hook '$repo_hook' exists but is not executable; ignoring it." >&2
fi

case "$hook_name" in
  push-to-checkout)
    # Presence-sensitive: exit 0 would tell git the worktree update was
    # handled. Emulate git's built-in updateInstead default instead: refuse
    # when worktree or index differ from HEAD, otherwise update both. The
    # cwd here is $GIT_DIR, which contains a file named HEAD, so the -- on
    # diff-index disambiguates the revision from that file.
    git update-index -q --ignore-submodules --refresh &&
    git diff-files --quiet --ignore-submodules -- &&
    git diff-index --quiet --cached --ignore-submodules HEAD -- &&
    git read-tree -u -m HEAD "$1"
    exit $?
    ;;
  proc-receive)
    # Presence-sensitive: speaks a pkt-line protocol no generic script can
    # emulate. Failing rejects the matched ref exactly as an absent hook
    # does; exit 0 would claim refs were handled when nothing handled them.
    exit 1
    ;;
  *)
    exit 0
    ;;
esac
