## Codex Remote Control

Codex remote control requires the container to be reachable via SSH. This local
feature depends on the [sshd feature][1] to launch an ssh server that listens on
port 2222. The consuming devcontainer must then publish that port in order to
reach the container's ssh server, e.g. by adding the following to the
`devcontainer.json` file:

```
{
  ...
  "appPort": ["127.0.0.1:2222:2222"]
}
```

See the [devcontainer documentation][2] for details

## Supported Codex runtime

Docker Desktop in Linux-container mode is the sole supported runtime for the
Codex sandbox integration. Native Linux Docker, rootless Docker, Podman, and
other Dev Container backends are unsupported.

The published image embeds these exact Docker security options:

The exact entries are `seccomp=unconfined` and `apparmor=unconfined`.

```json
"securityOpt": [
  "seccomp=unconfined",
  "apparmor=unconfined"
]
```

The embedded and published `capAdd` is exactly `[]`, so no Docker capabilities
are added. The default-security control must fail through the instrumented system Bubblewrap
path with `bwrap: pivot_root: Operation not permitted`. If that control begins
to pass, it is the retirement signal: reevaluate and redesign the outer runtime
before preserving either unconfined option.

## Outer and inner sandbox boundaries

The feature installs `/usr/bin/bwrap` as `root:root` with mode `4755`. Runtime
acceptance verifies that Codex selects this system executable instead of
Codex's bundled fallback.

The security options create a relaxed outer Docker boundary so Codex can
construct Codex's inner sandbox for commands it launches. The outer relaxation
is container-wide. Interactive shells, lifecycle scripts, and other non-Codex
processes do not receive Codex's inner sandbox and therefore run without its
filesystem isolation or in-process syscall restrictions.

Dev Container tooling merges image metadata with consumer configuration.
Consumer-supplied seccomp or AppArmor values in additional `securityOpt`
entries conflict with the image's settings and are unsupported; remove those
additional entries rather than attempting to override the embedded contract.

## Shared agent instructions

Codex reads its always-on guidance from `~/.codex/AGENTS.md`, which this Feature
mounts from the host's `~/.claude/CLAUDE.md` — a single shared file under two
names, separate from the `~/.agents/instructions` directory mount described
below. Bulk references that file points at are read from
`~/.agents/instructions`. The host must supply the canonical shared instruction
corpus from [hube/claude-home](https://github.com/hube/claude-home), including
`setup-recovery.md` and the worktree and orchestration consumers that reference
it. Updating a separate clone inside the container does not update a host bind
source.

This Feature owns only the container **target** path. The mount itself is
**consumer-declared**: you choose the host directory it reads from. Copy this
block into the top-level `mounts` array of your `devcontainer.json` — once for
the container, not per Feature — with `source` set to that directory:

```json
{
  "type": "bind,readonly",
  "source": "${localEnv:HOME}/.claude/instructions",
  "target": "/home/${localEnv:USERNAME:devcontainer}/.agents/instructions"
}
```

**The host directory you name as `source` must exist before you start the
container.** Docker rejects a bind mount whose host source is missing, and that
failure breaks container startup outright — before anything can report it. The
host file this Feature binds as `AGENTS.md` must exist for the same reason.
Docker names the offending path when this happens:

```
Error response from daemon: invalid mount config for type "bind":
bind source path does not exist: /Users/you/agent-instructions
```

To confirm the mount landed, list the target inside the container. It must
exist; an empty listing means either nothing was mounted onto it or the host
directory is itself empty, so check the host path before changing any JSON:

```bash
ls -ld ~/.agents/instructions && ls ~/.agents/instructions
```

If you never declare the mount, the container still starts. Codex loads
`AGENTS.md` normally, and only the referenced bulk detail is unavailable.

## Activate autonomous task startup

Startup recovery lets a desktop remote agent or delegate establish an isolated
branch and linked worktree after an eligible sandbox denial using Codex's
supported automatic approval review. The shared instructions classify the
failure; the running session's policy controls whether approval is available.
This configuration covers isolated task startup. Input retrieval also needs the
canonical retrieval guidance described below. Tool execution and task checks need
the check-capable guidance described in "Run authorized task checks". Signing,
publication and migration of incompatible persistent installations have separate
acceptance requirements.

The compatible subset is Docker Desktop in Linux-container mode with the
Feature's existing runtime contract, a readable always-on guidance file and
canonical bulk corpus, and an effective session policy exposing automatic review
and the execution tool's supported escalation argument. Feature defaults select
`approvals_reviewer = "auto_review"`; they do not prove the effective desktop or
delegate policy. A managed or user policy that prevents automatic review needs
an explicit policy decision before startup recovery can be enabled.

The example bulk mount above uses the canonical host clone at `~/.claude`.
For a new installation where that path does not exist, create its bind sources
on the Docker Desktop host:

```bash
git clone git@github.com:hube/claude-home.git "$HOME/.claude"
```

Do not replace an existing directory to run that command. For an existing
canonical clone, run the following on the host. Confirm that the remote names
`hube/claude-home` and that status prints no changes before proceeding:

```bash
git -C "$HOME/.claude" remote get-url origin
git -C "$HOME/.claude" status --short
```

Capture a rollback receipt before refreshing a clean clone:

```bash
guidance_receipt=$(mktemp "$HOME/codex-guidance-before.XXXXXX")
git -C "$HOME/.claude" rev-parse HEAD > "$guidance_receipt"
printf '%s\n' "$guidance_receipt"
git -C "$HOME/.claude" pull --ff-only
```

Each command must succeed; the receipt must contain the previous commit SHA.
Keep the printed receipt path. A dirty clone, a different remote, or a refused
fast-forward needs its installation owner to resolve that condition; leave its
files intact. A different consumer-selected mount source must already provide
the same canonical corpus before following the container checks below.

From the consuming project's directory on the host, recreate its container with
the installed Dev Container CLI:

```bash
devcontainer up --workspace-folder "$PWD" --remove-existing-container
```

The command must exit successfully. It replaces the container, while the
Feature's named Codex volume retains configuration, credentials and history.
Check what the recreated container reads by running these commands inside it as
its configured user:

```bash
cat ~/.codex/AGENTS.md
cat ~/.agents/instructions/setup-recovery.md
cat ~/.agents/instructions/worktree-isolation.md
```

All three reads must succeed. The always-on index must direct setup failures to
`setup-recovery.md`, and the worktree instructions must reference that same
recovery procedure. The recovery file must describe classification, inspection
of task-owned partial effects, and the supported automatic approval path.

Connect the desktop app to the recreated container using the SSH port published
in the remote-control section. Add a concrete alias to the host machine's
`~/.ssh/config`, substituting the configured container user if it differs:

```sshconfig
Host codex-container
  HostName 127.0.0.1
  Port 2222
  User devcontainer
```

From that host, run `ssh codex-container 'command -v codex'`. It must authenticate
and print the installed CLI path. In the desktop app, open **Settings >
Connections > SSH**, enable that alias, and select the container's project
folder. Start a new chat in that remote project, so it reads the refreshed
always-on context. These connection controls follow the
[official remote-connection guide](https://learn.chatgpt.com/docs/remote-connections#connect-to-an-ssh-host).
Request a compatibility report from that chat covering its runtime-provided
approval policy and execution tool, and the same values from a real delegate's
own received context. The report must identify `auto_review` and the supported
`require_escalated` argument in both contexts. Missing runtime policy or a
missing escalation argument is a harness integration dependency, even when the
config file has the right value. Maintainers establish startup availability with
the [live startup acceptance](MAINTAINERS.md#verify-autonomous-task-startup);
the input checks alone do not establish that outcome.

If a read fails, preserve its stdout/stderr and inspect the mounts in the
container:

```bash
findmnt -T ~/.codex/AGENTS.md
findmnt -T ~/.agents/instructions
```

A missing bulk file means the host source does not supply the required corpus.
Update that host source rather than a container clone. An always-on file that
lists in the directory but fails to read can be a stale single-file bind after
its host source was replaced. Restore the host source named by the mount and
recreate the devcontainer through the consuming project's normal container
lifecycle, then repeat the reads and open a fresh chat. Success means the files
are readable through their configured mounts and the new session consumes them;
a directory listing alone does not establish that.

A terminal startup diagnostic needs the failed command and captured output,
the effective parent/delegate policy, and the verified partial branch/worktree
state from the task's working notes. These distinguish a sandbox denial from an
approval rejection, ownership refusal, authorization failure, or ordinary
command failure. Approval does not supply missing authorization or permit
another task's worktree to be reused.

To roll back a refresh, use the saved receipt path on the host. First confirm
`git -C "$HOME/.claude" status --short` prints no changes; otherwise stop for the
installation owner rather than overwriting edits. Replace the example receipt
path below with the path printed before the refresh:

```bash
previous_guidance=$(cat /absolute/path/to/codex-guidance-before.XXXXXX)
git -C "$HOME/.claude" restore --source "$previous_guidance" -- \
  CLAUDE.md instructions
```

The restore must exit successfully and changes only the tracked guidance paths.
Recreate the container and reconnect with a new remote chat using the same steps
above, then repeat the guidance reads and compatibility report. The restored
host files can appear modified relative to its current branch; keep them until
the installation owner chooses the next guidance revision. Keep the persistent
Codex volume, unrelated configuration, authentication, session history, and
other tasks' worktrees intact.

## Retrieve authorized task inputs

Input retrieval uses the same automatic-review policy and shared guidance as
startup recovery, together with credentials for the requested repository. The
agent classifies a failed fetch or SSH transport operation, uses supported
approval for an eligible sandbox denial, then continues with the obtained input.
Approval cannot supply repository access or a missing host identity.

Activate the canonical corpus using the host refresh, container recreation and
new-chat steps in "Activate autonomous task startup" above. The mounted
`setup-recovery.md` must cover setup, fetch and required transport, and the
always-on index must direct input-retrieval failures to it. A readable
setup-only revision does not enable retrieval recovery. The parent and its real
delegate must each expose `auto_review` and `require_escalated` in their own
runtime context; this extension adds no broader permission default.

For SSH retrieval, the consuming image includes the SSH Feature's host-agent
socket and known-hosts wiring. The desktop connection may supply a forwarded
agent socket instead; inspect the running session rather than assuming that the
Feature's socket path is effective. From the container, inspect the selected
socket and its loaded public identities:

```bash
printf '%s\n' "$SSH_AUTH_SOCK"
ssh-add -l
```

An unreachable agent prevents authentication; restore the reported socket's
host/desktop forwarding. An agent with no identities needs an identity loaded
on the host with `ssh-add`. A remote credential rejection needs access for that
identity to the named repository. A DNS or connection failure outside the
sandbox needs connectivity to the named host. Preserve the failed command's
output in each case; repeated approval requests cannot repair those causes.

A chat can see an SSH configuration ownership error or agent access denial that
an ordinary container shell does not see. Request a diagnostic report comparing
the captured failure, the chat's effective restrictions and supported approved
transport diagnostics. Do not change system SSH ownership or replace SSH
configuration to work around that difference. If the approved diagnostic still
fails, its captured output identifies the host/desktop integration to repair.

The canonical procedure owns fetch destinations and bounded retries. Maintainers
establish retrieval availability through the
[live retrieval acceptance](MAINTAINERS.md#verify-autonomous-input-retrieval),
including regression of startup. To roll back retrieval guidance, use the saved
receipt and rollback steps above, preserving the Codex volume and unrelated
persistent state.

## Run authorized task checks

Task-check recovery lets the agent run authorized tools and project checks
through automatic approval after an eligible sandbox denial. It uses the same
session policy and canonical recovery procedure as startup and retrieval.
Approval permits an operation; it does not repair a missing dependency or turn
an ordinary failing test into a passing one.

Use the host refresh, container recreation and new-chat activation above. The
mounted `setup-recovery.md` and always-on index must cover task checks as well
as setup and retrieval. Confirm both the parent and a real delegate expose the
supported approval path in their own runtime context. The consumer must supply
the executables, interpreters and dependencies required by its tasks. This
extension adds no broader permission or runtime-security default.

A tool invocation can return output and an exit status alongside a reported
execution error. Request a diagnostic report retaining the complete command
result and comparing the default invocation with an eligible supported approved
invocation. A diagnostic invocation succeeding does not prove the project check
succeeded. A missing executable or dependency needs the named project
prerequisite restored; a failing assertion needs the reported project defect
corrected. A pending or interrupted check needs diagnosis and a completed run
before it supplies a result. Preserve the captured output when requesting help.

Maintainers establish the supported subset with [live task-check
acceptance](MAINTAINERS.md#verify-autonomous-task-checks), including startup
and retrieval regression in both seats. Input checks and draft guidance alone
do not establish consumed availability. To roll back guidance, use the saved
host receipt and rollback steps above, preserving the Codex volume,
credentials, history and unrelated task state.

## Publish authorized task output

Publication recovery lets a compatible desktop remote session use automatic
review after a sandbox denial while creating a signed commit, pushing it to an
authorized destination, or publishing its intended GitHub review artifact. The
configured signing identity, repository access, attribution requirements and
owner-only merge rule remain prerequisites. The process is to activate the
publication-capable corpus, verify the session's policy and credentials, then
have the authorized task verify its signature and published result by readback.

Use the host refresh, container recreation and new-chat activation in
"Activate autonomous task startup". The mounted recovery procedure must cover
SSH signing and Git/GitHub publication, and each seat must expose automatic
review and supported escalation in its own runtime context. This extension
changes no permission default or persistent credential. Existing compatible
sessions use their configured Git signing identity and forwarded SSH agent;
this Feature does not configure a signing identity or grant repository access.

Inspect the effective signing inputs inside the container:

```bash
git config --get gpg.format
git config --get commit.gpgsign
git config --get user.signingkey
ssh-add -l
```

The supported signing path uses SSH format, enabled commit signing, and a valid
configured public identity whose matching private identity is loaded in the
selected host agent. Missing signing settings need the installation owner to
restore that configuration. An unreachable agent needs its named forwarding
restored; an agent without the required identity needs that identity loaded on
the host. A sandbox-restricted diagnostic needs comparison through the supported
approval path before it can establish an identity failure.

The consumer supplies GitHub CLI and its persistent authentication volume
through the GitHub CLI configuration Feature. Inspect authentication without
printing a token:

```bash
gh auth status --hostname github.com
```

A rejected identity needs access to the requested repository and operation. An
unresolved destination needs an authorization decision before publication can
continue. A hook rejection needs the reported commit defect corrected. Preserve
the failing command's output when requesting a diagnostic report; repeated
approval cannot supply those prerequisites.

Request a publication report that verifies the commit signature, the remote
branch's intended commit, and the GitHub artifact's head and body. An ambiguous
failure can follow a completed push or artifact creation, so the report must
inspect existing results before retrying. Maintainers establish availability
with [publication acceptance](MAINTAINERS.md#verify-autonomous-publication),
including the earlier task flow in both seats. To roll back the guidance, use
the saved host receipt and rollback steps above, preserving authentication,
history, configuration and unrelated task state.

## Adopt recovery in a persistent installation

Adoption keeps the Codex volume and changes only the recovery settings you
choose. The process is to inspect existing settings and policy, select compatible
permissions, refresh the shared guidance, and verify a new remote chat and its
delegate. Reinstalling defaults does not activate recovery in an existing chat.

The Feature seeds missing configuration files and preserves files already present
in the target home. It does not merge new defaults into an existing `config.toml`.
Keep the named Codex volume when recreating the container; removing it would also
remove authentication and history.

Inspect the existing `~/.codex/config.toml` and any selected profile or trusted
project override before changing settings. The compatible recovery values are:

```toml
approval_policy = "on-request"
approvals_reviewer = "auto_review"
sandbox_mode = "workspace-write"
```

These are a compatible subset, not a replacement configuration. Preserve all
unrelated entries. If an existing value differs, the installation owner chooses
whether to change it; the Feature does not silently override that choice. Before
editing an existing file, save it on the Docker Desktop host, using the SSH alias
configured in "Activate autonomous task startup":

```bash
umask 077
config_backup=$(mktemp -d "$HOME/codex-config-before.XXXXXX")
ssh codex-container 'cat ~/.codex/config.toml' > "$config_backup/config.toml"
printf '%s\n' "$config_backup"
```

The SSH command must succeed before editing. Keep the printed host directory;
it survives container recreation. A copy elsewhere in the container's disposable
filesystem cannot supply rollback. If the configuration file does not exist,
record that fact on the host instead of saving an empty backup, then create it
with these settings. Otherwise edit only these entries in their existing
top-level locations, before any table header.

Configuration defaults can be overridden by a profile, project configuration or
the running client. Managed requirements can prohibit an approval reviewer,
approval policy or sandbox mode. Follow the [official configuration precedence
reference](https://learn.chatgpt.com/docs/config-file/config-basic#configuration-precedence)
to locate the layer responsible for a conflict. An administrator must resolve a
managed restriction; changing user defaults cannot override it. Keep the policy
intact and report the rejected setting and its source when requesting that
decision.

In the desktop remote chat, choose **Approve for me** from the permissions
control below the message composer. If it is absent, enable **Auto-review** under
**Settings > General > Permissions**, then select the mode in the chat. Enabling
it in settings alone does not change an existing chat. These controls follow the
[official permissions guide](https://learn.chatgpt.com/docs/permission-modes).
If organization policy disables the mode, have its administrator resolve that
restriction. Refresh the guidance and start a new chat using "Activate autonomous
task startup". Verify the runtime-provided policy and escalation argument in that
chat and its real
delegate. A config-file read or standalone CLI diagnostic cannot establish the
active desktop policy. If either context lacks automatic review or supported
escalation, leave activation unverified and request the named client or policy
integration to be repaired.

To roll back edits to an existing file, first confirm that restoring it will not
overwrite subsequent user changes. From the Docker Desktop host, set
`config_backup` to the saved host directory and restore through the same SSH
alias, including after container recreation:

```bash
ssh codex-container 'cat > ~/.codex/config.toml' < "$config_backup/config.toml"
```

The SSH command must succeed. If adoption created the file, remove only that
newly created file after confirming it contains no subsequent user changes.
Restore guidance using the separate saved guidance receipt above, recreate the
container with the same volume, and open a new remote chat. Preserve credentials,
history, other configuration and task worktrees.

## Creation and health failures

If container creation fails before the post-create hook runs, read the failed
`devcontainer up` output first — it is authoritative, and two different causes
land here. If it names a bind source that does not exist, a mount is declared
whose host path is missing; create that path and recreate the container (see
"Shared agent instructions" above). Otherwise Docker Desktop could not apply the
image's published runtime contract: confirm Docker Desktop is running Linux
containers, remove conflicting consumer `securityOpt` entries, and recreate the
container. Preserve the complete CLI output when requesting help.

If the post-create health check fails, Codex could not validate the ownership
and mode of system Bubblewrap or could not create and read a marker through
`codex sandbox -P :workspace`. Follow the problem, consequence, and remedy in
the hook diagnostic; its final clause contains the captured `stat`, Codex, or
cleanup output. Correct the reported installation or runtime problem, rebuild
the container, and rerun creation. There is no automatic fallback to a custom
profile, a different image, or an unsandboxed Codex command.

## Maintainer documentation

Maintainers can find local acceptance, publication, post-publication,
cleanup, and retirement procedures in the [maintenance guide](MAINTAINERS.md).

[1]: https://github.com/devcontainers/features/tree/main/src/sshd
[2]: https://containers.dev/implementors/json_reference/#image-specific
