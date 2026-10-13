# Maintaining the Codex local Feature

This is the operational authority for accepting and publishing Codex local
Feature changes. User-facing runtime requirements and troubleshooting remain
in [`NOTES.md`](NOTES.md).

Run every command from the repository root with Docker Desktop in
Linux-container mode. The runtime test rejects native Linux Docker, rootless
Docker, Podman, and other engines because they are not supported acceptance
targets.

## Local acceptance

Use a stable local image name so the runtime matrix and unrelated-consumer test
exercise the same build:

```bash
CODEX_RUNTIME_TEST_IMAGE=codex-runtime-test:acceptance \
  bash .devcontainer/local-features/codex/test/test-runtime.sh
bash .devcontainer/local-features/codex/test/test-image-consumer.sh codex-runtime-test:acceptance
bash .devcontainer/local-features/agent-skills/test/test-install-order.sh
```

Acceptance requires all three commands to exit zero. The runtime matrix must
show the default-security control failing through system Bubblewrap with
`bwrap: pivot_root: Operation not permitted`, every treatment and restoration
passing, and a final `REQUIRED_CAPABILITIES=` line matching the committed
`capAdd`. The unrelated consumer must report successful post-create health and
sandboxed patch persistence. The install-order test must report that feature
install order and the combined lifecycle command were verified.

If a command fails, the problem is that the supported-runtime contract has not
been accepted; merging could publish an image whose Codex sandbox is unusable.
Preserve the complete output, correct the reported build, Docker, cleanup, or
sandbox failure, and rerun all three commands before merging.

## Prepare disposable recovery inputs

Use one new acceptance directory, outside both actors' effective writable roots
for denial acceptance. Its parent must be writable by the container user through
supported approval. For a recipe-only probe, `/tmp` is sufficient; that probe
cannot establish a denial. Record the selected absolute directory externally.
The seed and protected worktrees below are linked worktrees of a disposable bare
repository. The protected subset consists of every pre-existing ref's object
and symbolic target, the bare `HEAD`, complete worktree registrations, the named
fixture bytes, and shared `FETCH_HEAD` including
its absence. Parent/delegate branches and paths are declared additions, not part
of that protected subset. `ownership.txt` is synthetic protected data, not a new
ownership protocol.

Decided (owner, 2026-10-12: [bounded bootstrap exception](https://github.com/hube/devcontainer/pull/98#issuecomment-6139134484)):
for this acceptance recipe only, the first linked seed may be created in a new
disposable bare repository before its ignore file exists. This overrides the
canonical manual worktree path and pre-creation ignore check for that first seed
only. Confirm the selected directory is new and contains no pre-existing refs,
worktrees or protected state. Commit the seed's ignore/protected fixtures before
creating subsequent worktrees under checked ignored roots. Production
repositories and other tasks retain the canonical procedure.

From this repository's task worktree inside the Linux devcontainer, set the
paths below. Run preparation with
supported approval when the selected directory requires it:

```bash
acceptance_root='/absolute/new/acceptance-directory'
mkdir "$acceptance_root"
acceptance_repo="$acceptance_root/repo.git"
acceptance_seed="$acceptance_root/seed"
acceptance_protected="$acceptance_seed/.worktrees/protected-<task>-<id8>"
git init --bare --ref-format=files "$acceptance_repo"
git --git-dir="$acceptance_repo" worktree add --orphan \
  -b fixture-seed "$acceptance_seed"
printf '.worktrees/\n' > "$acceptance_seed/.gitignore"
printf 'protected fixture bytes\n' > "$acceptance_seed/protected.txt"
printf 'synthetic ownership fixture\n' > "$acceptance_seed/ownership.txt"
```

Prepare a signed, attributed seed message using the canonical
[`committing.md`](https://github.com/hube/claude-home/blob/main/instructions/committing.md)
procedure. Keep the message in external working notes and set `acceptance_message`
to its absolute path. The fixture has no lint/typecheck/build configuration;
record those unavailable checks rather than claiming they ran. Then create the
seed and its protected worktree:

```bash
git -C "$acceptance_seed" add .gitignore protected.txt ownership.txt
git -C "$acceptance_seed" commit -F "$acceptance_message"
git -C "$acceptance_seed" verify-commit HEAD
git -C "$acceptance_seed" check-ignore .worktrees/.probe
git --git-dir="$acceptance_repo" worktree add \
  -b fixture-protected "$acceptance_protected" fixture-seed
git -C "$acceptance_protected" check-ignore .worktrees/.probe
```

The ignore check must identify `.worktrees/.probe`. Preserve this fixture if
preparation fails and classify the captured failure through the canonical
recovery procedure before retrying.

### Compare the protected subset

The acceptance-specific [state helper](test/recovery-state.py) captures refs,
complete registrations, SHA-256 digests of explicitly named synthetic files,
and shared fetch-receipt state. The recipe selects Git's files ref backend;
the helper rejects other backends and legacy symbolic-link ref storage rather
than returning a preservation result. It records immediate stored symbolic
targets, including unborn targets, and
direct objects from packed and loose refs. Symbolic refs have `oid: null`;
their target refs are protected independently. It runs real Git reads and does
not stub Git, Codex or SSH. Keep its JSON outputs outside the disposable
repository. The
maintained [control catalogue](https://github.com/hube-ai/agent-tools/blob/main/general/README.md)
is the discovery authority for existing verification tools; this helper handles
the feature's protected-subset comparison rather than published-body readback.

```bash
acceptance_state='.devcontainer/local-features/codex/test/recovery-state.py'
python3 "$acceptance_state" capture --repo "$acceptance_repo" \
  --file "$acceptance_protected/.gitignore" \
  --file "$acceptance_protected/protected.txt" \
  --file "$acceptance_protected/ownership.txt" \
  > "$acceptance_root/before.json"
```

Each actor obtains its own session identifier through the canonical committing
procedure. Before setup, record its task name and first eight session characters
in external notes. Set the following to those actual values, then assign distinct
branches and paths beneath the ignored root:

```bash
parent_task='actual-parent-task'
parent_id8='actual-parent-id8'
delegate_task='actual-delegate-task'
delegate_id8='actual-delegate-id8'
parent_branch="$parent_task-$parent_id8"
delegate_branch="$delegate_task-$delegate_id8"
parent_path="$acceptance_protected/.worktrees/$parent_task-$parent_id8"
delegate_path="$acceptance_protected/.worktrees/$delegate_task-$delegate_id8"
```

Each actor follows canonical worktree setup using its recorded branch/path,
including the pre-creation ignore check. After their authorized additions,
repeat the same capture invocation with output `after.json`, then compare:

```bash
python3 "$acceptance_state" compare "$acceptance_root/before.json" \
  "$acceptance_root/after.json" \
  --allow-ref "refs/heads/$parent_branch" --allow-ref "refs/heads/$delegate_branch" \
  --allow-worktree "$parent_path" --allow-worktree "$delegate_path"
```

A permitted addition never permits changing a baseline entry. For retrieval,
add each actor's predeclared input ref to the allowlist; for publication, declare
its destination repo and capture/compare that repo separately. Use the identical
protected file list for each before/after capture. Preserve raw command results.

Prove the comparator on an actual changed protected file: append a line to
`protected.txt`, capture `changed.json` with the same invocation, and run the
same compare command with `changed.json` in place of `after.json`. It must reject
the altered digest. Restore only that task-created file using its seed blob:

```bash
git --git-dir="$acceptance_repo" show fixture-seed:protected.txt \
  > "$acceptance_protected/protected.txt"
```

Recapture with the original file list and confirm preservation again. The
snapshot's `refs` map holds each ref's `oid` and `symbolic_target`; `head` holds
the bare symbolic target or detached object. Its `worktrees` map holds the
complete porcelain block keyed by path. Produce synthetic controls from the
captured actual snapshot, changing an entry selected from the original baseline:

```bash
python3 - "$acceptance_root" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
baseline = json.loads((root / "before.json").read_text())
for field in ("refs", "worktrees"):
    changed = json.loads((root / "after.json").read_text())
    key = next(iter(baseline[field]))
    if field == "refs":
        changed[field][key]["oid"] = "deliberately-altered"
    else:
        changed[field][key] += "\nsynthetic-alteration"
    assert changed[field][key] != baseline[field][key]
    (root / ("changed-" + field + ".json")).write_text(json.dumps(changed))
PY
```

Run the same allowlisted compare invocation with each changed JSON in place of
`after.json`; both must fail. These are synthetic JSON controls. Never mutate a
production baseline or another task's worktree.

### Exercise startup classifications

Use a separate copy of this disposable topology in `/tmp` for safe cases. Keep
these results separate from the outside-root denial acceptance:

| Case | Input and operation | Retained evidence |
| --- | --- | --- |
| Safe setup | Create a new branch/worktree from `fixture-seed` in the writable fixture. | Actual setup result and a subsequent file write/status in that actor's worktree. |
| Ordinary failure | Run `git worktree add` with a new task path and nonexistent source ref `acceptance-missing-ref`. | Captured Git failure, absent task branch/path after inspection, and ordinary-failure classification. |
| Ownership refusal | Attempt to add `fixture-protected` at a different new path while that branch is registered in the protected worktree. | Captured refusal, unchanged protected registration/ref and no force or ownership bypass. |
| Rejected approval | Use an independently observed automatic-review rejection if available; otherwise describe a hypothetical rejected request. | Matched planned action/decision for an observed rejection, or an explicit hypothetical label; no retry bypass. |

Classify each result using
[`setup-recovery.md`](https://github.com/hube/claude-home/blob/main/instructions/setup-recovery.md).
A safe result and ordinary failure do not demonstrate escalation. The ownership
case probes the already-registered branch refusal in our synthetic fixture; it
does not grant permission to operate on another task's real branch.

## Verify autonomous task startup

This live acceptance exercises the desktop remote parent and a real delegate,
using disposable Git state. It complements the repository-input checks; a
standalone CLI probe does not establish desktop or delegated approval.

Run the input checks from a task-linked worktree of this repository:

```bash
python3 .devcontainer/local-features/codex/test/test-feature-config.py
bash .devcontainer/local-features/codex/test/test-documentation.sh
```

For live acceptance, connect a fresh desktop chat using the activation steps in
`NOTES.md`. Authorize and run "Prepare disposable recovery inputs" above, choosing
the acceptance directory outside both seats' effective writable roots. Capture
`before.json` before either seat's task additions. Keep the seed and protected
worktrees intact throughout the scenario.

Give the delegate its own authorized branch/destination and the mounted recovery
procedure's path. Each seat attempts `git worktree add` with its default policy,
reads `~/.agents/instructions/setup-recovery.md` after failure, inspects the
partial refs/registrations/destination, and follows that canonical procedure.
The source branch and intended destination must be recorded before the attempt.
Require each seat to read its own effective permissions and tool schema, rather
than inheriting the parent's policy report. After setup, each performs a write
and Git status in its own worktree, with separate supported approval if the
continuation command also needs it. Record each command's actual status/output;
seeded partial branches must be identified as fixtures rather than failed-attempt
effects.

Acceptance requires a real default sandbox denial and one successful supported
automatic-review setup retry for each seat, subsequent actions in distinct
worktrees, and readback of their written files. Compare the protected fixture's
refs, registration and any ownership-record fixture against the captured
baseline; intentional parent/delegate additions are the only allowed changes.
Prove the preservation comparison rejects a deliberately changed baseline.
Exercise safe setup and ordinary command failure separately; refused approval
and ownership-refusal classification controls must retain their stop outcomes.
Label hypothetical controls as hypothetical. A tool that supplies no independent
reviewer-decision record cannot establish that provenance.

Retain the raw outputs and final comparison in task working notes, and publish
only verified outcomes on the review artifact. A passed input suite alone, a
manually approved retry, or a setup without a captured denial is insufficient.
Keep the disposable worktrees for diagnosis; removal requires the owner's
specific direction. Startup availability also requires the activation procedure
and its reader-proxy dispositions to be verified before the unit is complete.

## Verify autonomous input retrieval

Retrieval acceptance extends the live startup scenario above. First activate the
retrieval-capable mounted corpus through `NOTES.md`, then rerun the repository
input and documentation commands and the affected parent/delegate startup
acceptance. A candidate file read from an implementation worktree is draft
validation; it does not establish mounted activation.

Authorize a read-only source repository that both seats may fetch over the
configured SSH transport. Record its URL, source ref and required
repository-relative file path before the attempt. Select an existing file that
both seats must read to continue the authorized task. In the disposable
acceptance repository, capture all existing refs, registrations,
protected fixture bytes and any shared `FETCH_HEAD` before retrieval. Assign a
fresh input destination ref to each seat so intentional additions can be
identified. Each seat follows the mounted canonical recovery procedure from its
own linked worktree, attempts the authorized fetch with default policy, and
inspects partial effects before any supported retry. Record each actual command,
exit status and captured output, plus the effective policy from that seat's own
context. No transport, Codex or Git runtime is stubbed in this live scenario.

Each seat must read the fetched object's intended file and perform a subsequent
action in its own workspace. Compare the fetched source against the authorized
remote ref, and re-read both continuation results. Compare every original ref,
registration, protected fixture byte and shared fetch receipt against baseline;
only the declared task-owned input refs and startup additions may differ. Prove
the same preservation comparator rejects a deliberately changed baseline.

Acceptance requires exercised default sandbox denial, bounded supported
approval and successful authorized SSH retrieval for the parent and actual
delegate. Distinguish a sandbox-restricted agent/configuration from an
unreachable agent, an empty agent, rejected credentials and network failure;
use isolated diagnostic controls without replacing real credentials or system
SSH configuration. Label hypothetical authorization/rejected-approval cases
explicitly and retain their stop outcomes. Exercise a safe successful case and
an ordinary failed command without classifying either as a recovered denial.

Retain evidence in the task's external working notes. Publish the verified
supported subset, the activation and startup-regression results, and any
remaining integration dependency. Input checks, a standalone CLI run, draft
validation or an unobserved approval path alone do not establish retrieval
availability. Reader-proxy review and its dispositions are required for changed
operator guidance before this delivery is complete.

### Diagnose transport and signing with isolated inputs

Use invocation-scoped socket selection for these diagnostic probes. They do not
alter the real agent, credentials or global Git/SSH settings. If the execution
sandbox prevents even the diagnostic, classify that failure and use the
canonical supported approval route; a sandbox-restricted socket is not evidence
that the corresponding agent is absent or empty.

```bash
transport_root=$(mktemp -d)
if SSH_AUTH_SOCK="$transport_root/absent.sock" ssh-add -l \
  > "$transport_root/absent.log" 2>&1; then
  absent_status=0
else
  absent_status=$?
fi
cat "$transport_root/absent.log"
printf 'Absent-socket status: %s\n' "$absent_status"
ssh-agent -a "$transport_root/empty.sock" -s > "$transport_root/agent.env"
empty_pid=$(sed -n 's/^SSH_AGENT_PID=\([0-9]*\);.*/\1/p' \
  "$transport_root/agent.env")
if SSH_AUTH_SOCK="$transport_root/empty.sock" ssh-add -l \
  > "$transport_root/empty.log" 2>&1; then
  empty_status=0
else
  empty_status=$?
fi
cat "$transport_root/empty.log"
printf 'Empty-agent status: %s\n' "$empty_status"
```

The nonexistent socket must report that the agent cannot be reached. The
created, reachable empty agent must instead report no identities. An unexpected
result leaves the diagnostic case unestablished; retain it, inspect the selected
socket and agent process, and repeat only after correcting that fixture.

Generate a disposable required identity, then remove its private key before the
missing-identity probe. The retained public key cannot be supplied by the empty
agent:

```bash
ssh-keygen -q -t ed25519 -N '' -f "$transport_root/required-key"
rm "$transport_root/required-key"
printf 'synthetic signing input\n' > "$transport_root/message"
if SSH_AUTH_SOCK="$transport_root/empty.sock" ssh-keygen -Y sign \
  -f "$transport_root/required-key.pub" -n git "$transport_root/message" \
  > "$transport_root/signing.log" 2>&1; then
  signing_status=0
else
  signing_status=$?
fi
cat "$transport_root/signing.log"
printf 'Missing-identity signing status: %s\n' "$signing_status"
```

This failure must identify the unavailable signing identity separately from an
unreachable socket or empty-agent inspection. Retain the actual primary failure;
it does not establish rejection by a remote repository. Exercise genuine remote
credential rejection only at a separately authorized destination; otherwise
label that case hypothetical.

After recording the diagnostics, stop only this fixture's agent and remove its
remaining synthetic signing inputs, keeping the captured logs:

```bash
SSH_AUTH_SOCK="$transport_root/empty.sock" SSH_AGENT_PID="$empty_pid" ssh-agent -k
rm "$transport_root/required-key.pub" "$transport_root/message"
```

Confirm the real `SSH_AUTH_SOCK`, signing configuration and public identities
still match their pre-probe readings. Do not use these fixtures as a substitute
for the real configured identity in publication acceptance.

## Verify autonomous task checks

Extend the live startup and retrieval scenario with a representative tool or
check in each seat's own disposable linked worktree. The concrete fixture below
uses Node, supplied by this consumer's commit-attribution Feature dependency;
the recovery procedure applies independently of the tool or programming
language. Run the input and documentation commands above before live
acceptance. Read the candidate canonical procedure for draft validation;
completion requires the merged check-capable corpus to be mounted and consumed
through the `NOTES.md` activation path by both the desktop parent and an actual
delegate. Record each seat's own effective policy and tool schema.

Authorize fixture preparation and its outputs before execution. Save this as
`node-check.cjs` in each seat's own disposable linked worktree, using supported
approval for preparation if needed:

```javascript
const { spawnSync } = require('node:child_process');
const output = process.argv[3];
if (!output || !require('node:path').isAbsolute(output)) {
  throw new Error('An authorized absolute output path is required.');
}
const cases = {
  good: ['node', ['-e',
    'require("node:fs").writeFileSync(process.argv[1], "fixture child ran\\n")',
    output]],
  broken: ['node', ['-e', 'process.exit(7)']],
  missing: ['acceptance-missing-command', []],
};
const mode = process.argv[2];
if (!Object.hasOwn(cases, mode)) {
  throw new Error('Unknown fixture mode; no check selected; use good, broken or missing.');
}
const [command, args] = cases[mode];
const result = spawnSync(command, args, { encoding: 'utf8' });
console.log(JSON.stringify({
  mode, command, args, node: process.version,
  status: result.status, signal: result.signal,
  error: result.error ? { code: result.error.code, message: result.error.message } : null,
  stdout: result.stdout ?? null, stderr: result.stderr ?? null,
}));
process.exitCode = result.error ? 1 : (result.status ?? 1);
```

Prepare a separate output directory outside each actor's effective writable
roots, writable by the container user through supported approval. Set
`check_output` to that directory's `parent.out` or `delegate.out` for the relevant
actor; authorize those exact files before execution. Each actor reads its own
runtime writable roots and confirms the output parent is excluded. The good
child must create the selected file, so stdout-only execution cannot substitute
for the restricted operation. Do not target credentials or production files.

From that same worktree, run `node node-check.cjs good "$check_output"` with
default policy. Run `node node-check.cjs broken "$check_output"` and
`node node-check.cjs missing "$check_output"` separately, retaining each
invocation's exit status and complete output. The fixture
retains attached errors instead of normalizing them away. Only an eligible
sandbox denial reaches an approved retry of the identical invocation; an
ordinary missing executable does not. After recovery, read back the selected output file and require the good
invocation to complete successfully and the broken invocation to remain
nonzero.

Retain the complete Node child result (`status`, `signal`, `error`, `stdout`,
`stderr`) and the invoking command's status/output. Classify the observed
failure through the canonical procedure and inspect outputs before any
supported approved retry. Keep an attached permission error even if the child
supplies output or a status. Do not infer sandbox denial from a pending check
or an ordinary test failure alone. No Node, OS utility or Codex runtime is
stubbed by this live scenario.

Each seat must exercise a real eligible denial, a bounded supported automatic
approval retry and a completed successful check invocation. Keep independent
reviewer-decision records for the operations; executor success alone cannot
establish approval provenance. In this Codex integration, inspect reviewer
rollout files under the effective Codex home's `sessions/` directory (the
runtime's `CODEX_HOME`, or `~/.codex` when unset). Select the acceptance's
records by matching its authorized command and fixture path in the reviewer
user message's `Planned action JSON:`. Pair that action with the subsequent
reviewer assistant JSON decision containing `outcome`; retain the source file,
action and decision outside repositories. Executor tool-output records are not
reviewer decisions. If the harness does not expose these independent reviewer
records, report that integration dependency and leave approval provenance
unverified. The deliberately broken check must remain a failure through
approval, and a missing executable must retain its ordinary failure
classification. Record hypothetical rejection/authorization controls as
hypothetical. Then perform and re-read an authorized continuation in each
seat's own worktree.

Rerun the earlier startup and SSH-retrieval acceptance in both seats against
the same mounted corpus. Compare every original ref, registration, protected
file, shared fetch receipt and retained output against baseline, allowing only
the declared task additions. Prove the preservation comparator rejects changed
baseline entries. Retain commands, raw outputs and comparisons outside
repositories; publish verified supported-subset and activation results together
with remaining dependencies. A standalone CLI probe, input suite or candidate
worktree read does not establish desktop/delegate availability. Changed
operator guidance requires reader-proxy review before this delivery is
complete. If no reviewer is designated, request an owner-designated reviewer in
an owner-addressed comment on the open PR. Follow
`~/.agents/instructions/review-protocol.md` ("Reader-proxy: operational half")
to obtain the relayed report and discharge each finding; the author does not
dispatch a reviewer of their own work.

## Verify autonomous publication

Extend consumed startup, retrieval and task-check acceptance with SSH signing,
authorized push and the intended GitHub review artifact. Run the input and
documentation suites above. Draft validation reads the candidate canonical
procedure; completion requires the merged publication-capable corpus to be
mounted and consumed by the actual desktop parent and delegate through the
`NOTES.md` activation path. Record each seat's effective policy and supported
escalation argument.

Authorize a disposable task repository and specific publication destinations
before execution. For a push probe, create a new bare destination outside the
seats' writable roots through supported approval; record its absolute path in
external working notes. Give each seat a distinct destination branch and leave
all existing refs and protected fixtures intact. A local bare destination tests
Git publication under filesystem restrictions; record it separately from an SSH
remote push. A full delivery also needs the configured SSH transport and the
intended artifact in an authorized GitHub repository. A fixture commit intended
for a PR must descend from that repository's selected base so its diff can be
reviewed.

In each seat's own disposable linked worktree, prepare an authorized file and
commit message using the attribution and co-author requirements in
`~/.agents/instructions/committing.md`. Record the configured signing identity
and inspect its selected agent through authorized diagnostics. Do not replace
real credentials or change global Git/SSH configuration. Stage only the fixture
file, attempt the signed commit with default policy, and capture its complete
result. After a failure, read the worktree, index and HEAD before following the
canonical bounded recovery procedure. Retain any completed signed commit.

Verify the created commit through Git's signature verifier and read its message
trailers:

```bash
git verify-commit HEAD
git log -1 --pretty=%B | git interpret-trailers --parse
```

From that worktree, push the intended commit to the pre-authorized destination
branch, using default policy first. Capture failures and inspect the destination
ref before retrying; if it already contains the intended commit, continue from
that result. Otherwise classify the failure and recover only an eligible denial.
Read back the destination with `git ls-remote <destination> <full-ref>` and
compare it with `git rev-parse HEAD`. Record the actual source, destination,
command, output and status outside repositories.

For GitHub publication, record the authorized repository, base, head branch and
intended artifact before attempting creation or update. Use a file-backed body
with the required identity and metadata. Inspect the artifact after an ambiguous
failure instead of creating a duplicate. Verify its remote head and complete
body through the GitHub interface after success. Only the authorized agent role
publishes: a delegate's signed commit and push probes do not grant it an author's
communication mandate. The parent publishes the review artifact when that role
owns it.

For a pull request, set the values below from the authorized task: the repository
as `OWNER/REPO`, its selected base and published task branch, and a complete body
file. Replace the example values before running commands; the body file must
already contain the required attribution. List existing artifacts before
creation, including closed ones:

```bash
publication_repo='OWNER/REPO'
publication_base='main'
publication_branch='TASK_BRANCH'
publication_title='Reviewable task output'
publication_body='/absolute/path/to/pr-body.md'
gh pr list --repo "$publication_repo" --state all \
  --head "$publication_branch" --json number,url,baseRefName,headRefOid,body
```

If no intended artifact exists, create it and retain the URL printed by the
command. If one already exists, retain its URL and inspect it instead:

```bash
gh pr create --repo "$publication_repo" --base "$publication_base" \
  --head "$publication_branch" --title "$publication_title" \
  --body-file "$publication_body" --reviewer hube
```

Set `publication_pr` to that returned or listed URL. Read the complete artifact
and the local intended commit; compare the base, head and body with the recorded
inputs. An authorized body update uses the same file, followed by another read:

```bash
publication_pr='https://github.com/OWNER/REPO/pull/NUMBER'
gh pr view "$publication_pr" --repo "$publication_repo" \
  --json url,baseRefName,headRefName,headRefOid,title,body
git rev-parse HEAD
gh pr edit "$publication_pr" --repo "$publication_repo" \
  --body-file "$publication_body"
gh pr view "$publication_pr" --repo "$publication_repo" \
  --json url,baseRefName,headRefName,headRefOid,title,body
```

Capture each invocation's complete result and apply the canonical failure
classification before any retry. After an ambiguous creation result, repeat the
list/read step; do not repeat creation until the artifact's absence is verified.
A successful edit still requires complete body and head readback.

Keep independent automatic-review action/decision records as described in
"Verify autonomous task checks"; a successful command does not establish
approval provenance. Exercise a real signing/publication sandbox denial and
bounded approved continuation, a safe successful operation, and an ordinary
hook or command failure that remains failed. Use isolated absent/empty agent
sockets or a disposable signing configuration for identity-failure diagnostics;
keep the real signing configuration and host credentials intact. Label rejected
approval, rejected destination and credential-rejection classification controls
hypothetical unless actually exercised. No Git, SSH or Codex runtime is stubbed
in these live scenarios.

Re-read each seat's continuation and compare all protected baseline state and
retained outputs after the complete flow. Prove that changed-baseline controls
are rejected. Rerun startup, SSH retrieval and check acceptance against the same
consumed corpus in both seats. Publish the supported subset and any unverified
integration dependency. Candidate probes, a local push alone or an unsigned
commit do not establish the full delivery. Changed operator guidance owes the
owner's designated reviewer and the canonical reader-proxy/disposition process;
the author does not dispatch their own review. Leave OpenSpec publication marks
unchecked until reviewed implementation and consumed acceptance are complete.
For `enable-codex-autonomous-recovery`, these are delivery 4 checkboxes in
[`tasks.md`](../../../openspec/changes/enable-codex-autonomous-recovery/tasks.md).
OpenSpec is a contributor prerequisite, not installed by the Codex Feature.
Use the [OpenSpec setup authority](https://github.com/Fission-AI/OpenSpec#quick-start)
for installation. From this repository root, preflight the executable before
locating the current task source paths and lines:

```bash
if command -v openspec; then
  openspec --version
else
  printf '%s\n' 'OpenSpec is absent from PATH.' \
    'Change tracking cannot run in this shell.' \
    'Install OpenSpec using its linked setup authority, then repeat this preflight.' >&2
  false
fi
```

Continue only when availability and version inspection succeed. Then run:

```bash
openspec instructions apply --change enable-codex-autonomous-recovery --json
```

Read each returned source location before changing its checkbox; rerun the
command after a completed task mark to verify the tracking result. The tracking
file is maintained by the OpenSpec change workflow, not generated by a
publication command.

## Verify persistent-installation adoption

Run the input and documentation suites from "Verify autonomous task startup".
The configuration-copy check examines our installer arguments and rejects removal
of the preservation option; it does not stub or unit-test rsync or Codex behavior.

### Prepare and verify configuration-copy fixtures

Translate only the installer's home-copy invocation to disposable targets. The
source is this task worktree's committed `home/`; the production target is
`/home/${_CONTAINER_USER}`. In the probe, the target is a new directory beneath
`copy_root`, owned by the current non-root user. The ownership arguments select
that user and group, and the preservation and mode arguments stay those of
[`install.sh`](install.sh). Do not run the complete installer against a fixture,
change `HOME` or `CODEX_HOME`, or read real authentication into it.

From this repository root inside the Linux devcontainer:

```bash
copy_root=$(mktemp -d)
copy_source="$PWD/.devcontainer/local-features/codex/home"
copy_user=$(id -un)
copy_group=$(id -gn)
mkdir -p "$copy_root/fresh/.codex" "$copy_root/persistent/.codex"
for copy_target in "$copy_root/fresh" "$copy_root/persistent"; do
  printf '{"synthetic":"not-a-credential"}\n' > "$copy_target/.codex/auth.json"
  printf 'synthetic closed history\n' > "$copy_target/.codex/history.jsonl"
  printf 'unrelated = "retain me"\n' > "$copy_target/.codex/unrelated.toml"
done
printf 'approvals_reviewer = "user"\nunrelated = "retain me"\n' \
  > "$copy_root/persistent/.codex/config.toml"
```

The named synthetic files are the protected subset; fresh configuration is an
intentional new output. Capture their baseline with the same helper:

```bash
copy_files=()
for copy_target in "$copy_root/fresh" "$copy_root/persistent"; do
  for copy_name in auth.json history.jsonl unrelated.toml; do
    copy_files+=(--file "$copy_target/.codex/$copy_name")
  done
done
copy_files+=(--file "$copy_root/persistent/.codex/config.toml")
python3 "$acceptance_state" capture --repo "$acceptance_repo" \
  "${copy_files[@]}" > "$copy_root/copy-before.json"
```

Run the mapped invocation for both targets, preserving failures in the aggregate:

```bash
copy_failed=0
for copy_target in "$copy_root/fresh" "$copy_root/persistent"; do
  if rsync -rp --ignore-existing --chown="$copy_user:$copy_group" \
    --chmod=D755,F644 "$copy_source/." "$copy_target/"; then
    :
  else
    copy_failed=1
  fi
done
test "$copy_failed" -eq 0
```

Continue only after each invocation succeeds. Verify the fresh configuration
against the committed source, then repeat the same capture command into
`copy-after.json` and compare it with `copy-before.json` with no allowed additions:

```bash
cmp "$copy_source/.codex/config.toml" "$copy_root/fresh/.codex/config.toml"
python3 "$acceptance_state" capture --repo "$acceptance_repo" \
  "${copy_files[@]}" > "$copy_root/copy-after.json"
python3 "$acceptance_state" compare \
  "$copy_root/copy-before.json" "$copy_root/copy-after.json"
stat -c '%U:%G %a %n' "$copy_root/fresh/.codex" \
  "$copy_root/fresh/.codex/config.toml"
```

The readback must identify the selected user/group, directory mode `755` and
configuration mode `644`. Add the newly seeded fresh `config.toml` to the
repeated-copy baseline using `copy_files+=(--file "$copy_root/fresh/.codex/config.toml")`
and capture `repeat-before.json` with that list. Repeat the same copy invocations and
capture/compare that full named subset. Append a line to the synthetic persistent
`auth.json`, recapture, and demonstrate that the same comparator rejects the
changed bytes; restore its original synthetic bytes and compare again. Retain
these as copy-wiring probes, with source revision and rsync version. They do not
establish desktop installation or third-party rsync guarantees.

### Capture live adoption separately

Use the actual remote user's effective Codex home, not the synthetic targets.
Before adoption, keep the configuration backup required by `NOTES.md`; record
its digest and the applicable managed-policy path without credential contents.
For authentication, retain `codex login status` and, where a file cache exists,
a local digest of that cache. If credentials use a keychain, record that storage
boundary and status instead of inventing a file baseline.

Record a history boundary before changing anything: select completed session
files for exact digest comparison, and for any append-only history file retain
its byte length and a digest of that prefix. After adoption or rollback, hash
that same prefix and confirm the current length is not shorter. Treat newly
created sessions and verified appended history as activity, not preserved
whole-file bytes. A rewrite inside the protected prefix is a failure; stop other
writers or diagnose it rather than allowlisting an arbitrary change. Retain the
selected paths, lengths and digests privately outside repositories, never the
credential or transcript contents.

Run this capture in the remote user's login shell inside the selected Linux
devcontainer before adoption or rollback. Select a new private notes directory
on a host bind mount or separately retained storage, outside repositories. It must survive the
container recreation; ephemeral container `/tmp` is unsuitable for that boundary.
Do not send its configuration backup to a public artifact:

```bash
adoption_home="${CODEX_HOME:-$HOME/.codex}"
adoption_before='/absolute/private/persistent/notes/adoption-before'
umask 077
mkdir "$adoption_before"
cp "$adoption_home/config.toml" "$adoption_before/config-before.toml"
sha256sum "$adoption_home/config.toml" > "$adoption_before/config.sha256"
codex login status > "$adoption_before/auth-status.txt" 2>&1
if [[ -f "$adoption_home/auth.json" ]]; then
  sha256sum "$adoption_home/auth.json" > "$adoption_before/auth.sha256"
fi
adoption_history="$adoption_home/history.jsonl"
if [[ -f "$adoption_history" ]]; then
  stat -c %s "$adoption_history" > "$adoption_before/history.size"
  head -c "$(cat "$adoption_before/history.size")" "$adoption_history" \
    | sha256sum > "$adoption_before/history-prefix.sha256"
else
  printf 'absent\n' > "$adoption_before/history.absent"
fi
```

Capture a selected completed session similarly with `sha256sum`, after checking
its exact session identity and completed status. For Codex desktop, ask an agent
with the exposed `read_thread` tool to read that exact chat and host. Require its
latest turn's `status` to be `completed` and no active turn; record that readback
privately and keep the selected chat inactive during exact-file comparison.
Match the rollout's `session_meta.id` to the selected chat ID. If the tool is
unavailable or the chat resumes, use a recorded length/prefix boundary instead;
do not infer completion from file age or a final-looking transcript line.
Record keychain or managed-policy paths separately when applicable.
Every capture command must succeed; a missing required configuration or failed
status command leaves that capture incomplete and requires diagnosis.

After adoption or rollback, retain the new authentication status and digest,
compare unrelated configuration values with the saved TOML, and verify the
history prefix where it existed:

```bash
codex login status > "$adoption_before/auth-status-after.txt" 2>&1
if [[ -f "$adoption_before/auth.sha256" ]]; then
  sha256sum "$adoption_home/auth.json" > "$adoption_before/auth-after.sha256"
  cmp "$adoption_before/auth.sha256" "$adoption_before/auth-after.sha256"
fi
if [[ -f "$adoption_before/history.size" ]]; then
  test "$(stat -c %s "$adoption_history")" \
    -ge "$(cat "$adoption_before/history.size")"
  head -c "$(cat "$adoption_before/history.size")" "$adoption_history" \
    | sha256sum > "$adoption_before/history-prefix-after.sha256"
  cmp "$adoption_before/history-prefix.sha256" \
    "$adoption_before/history-prefix-after.sha256"
fi
```

Run prefix pipelines in a shell with `set -o pipefail`, so a failed read cannot
become a digest of empty input. Recheck the selected completed-session digests
with the same file list. If authentication bytes changed, retain that mismatch
and diagnose credential refresh versus loss using the authentication status;
do not claim byte preservation merely because login still works. When history
was absent, record any newly created history as activity rather than a matching
prior file. This live readback is separate from synthetic copy acceptance.

After each installation's adoption and rollback, compare the unrelated
configuration values against the saved configuration, repeat authentication
status and credential-storage readback, and check the selected history boundary.
Record intended policy/guidance changes separately. Verify effective policy in a
new desktop chat and real delegate after reconnection. A fixture comparison or
an authenticated shell does not establish that a desktop session consumed the
adopted policy.

The two supported installation paths are a fresh container with new Codex state
and an existing installation retaining its persistent Codex volume. Follow the
adoption steps in `NOTES.md` on each path. To prepare the fresh path on the
Docker Desktop host, use a new disposable consumer directory outside Git
repositories. Complete the CLI and host-mount prerequisites in `NOTES.md` first.
Choose an unused local SSH port in place of `UNUSED_LOCAL_PORT`:

```bash
fresh_root=$(mktemp -d "$HOME/codex-recovery-fresh.XXXXXX")
mkdir "$fresh_root/.devcontainer"
cat > "$fresh_root/.devcontainer/devcontainer.json" <<'JSON'
{
  "image": "ghcr.io/hube/devcontainer:latest",
  "appPort": ["127.0.0.1:UNUSED_LOCAL_PORT:2222"]
}
JSON
printf '%s\n' "$fresh_root"
```

Replace the port placeholder in that task-created file, then run
`devcontainer up --workspace-folder "$fresh_root"`. Retain its successful
`containerId` as `fresh_container`. On the host, read the attached Codex volume:

```bash
docker inspect "$fresh_container" --format \
  '{{range .Mounts}}{{if eq .Destination "/home/devcontainer/.codex"}}{{.Type}} {{.Name}}{{end}}{{end}}'
```

Require `volume` and a newly created volume name distinct from the existing
installation's corresponding inspect result; a reused volume is not the fresh
path. Retain both names privately. Authenticate only if the fresh login-status
check requires it, then connect a separate desktop SSH alias using `NOTES.md`.
Recreation of that same consumer supplies the retained-volume path; do not
remove either volume as a substitute for rollback.

Record the selected user configuration
and applicable managed requirements without copying credentials. Verify a compatible configuration and deliberately
incompatible reviewer, approval-policy and sandbox settings are distinguished;
verify a managed restriction remains binding. A native configuration diagnostic
is invocation evidence only, not the policy of an active chat.

For each installation path, open a new desktop remote chat and a real delegate.
Each reads its own runtime policy and escalation schema. Repeat the complete
startup, retrieval, checks and publication flow above, including concurrent
distinct worktrees, denial/automatic-review records and protected-state controls.
Read back unrelated configuration, authentication and history after adoption and
rollback. A surrogate fixture, standalone CLI run or compatible existing chat
does not establish the fresh-container path. Leave tasks 5.1–5.4 unchecked until
their respective specified implementation, installation, policy and review
evidence is complete; name any host/client-only verification still owed.

Changed operator guidance requires the owner's designated reviewer and the
reader-proxy/disposition process. Before claiming any issue complete, follow
[proposal Impact](../../../openspec/changes/enable-codex-autonomous-recovery/proposal.md#impact)
and read the specific issue's current body and ruling. Issue maintainer 01a11490
records the owner-directed dispositions for [Git state](https://github.com/hube/devcontainer/issues/74#issuecomment-6030966274),
[Node](https://github.com/hube/devcontainer/issues/75#issuecomment-6030967807), and
[SSH](https://github.com/hube/devcontainer/issues/76#issuecomment-6030968321).
Those recorded dispositions override their original non-elevated closure criteria with not-planned outcomes.
Automatic recovery does not establish those original criteria as implemented.
Independent [validator](https://github.com/hube/devcontainer/issues/67) and
[alias](https://github.com/hube/devcontainer/issues/77) criteria remain their own.

## Publication

Merging to `main` triggers
[`.github/workflows/publish.yaml`](../../../.github/workflows/publish.yaml),
which builds and pushes `ghcr.io/hube/devcontainer:latest`. Select the full
merge commit SHA from the intended merged PR's `mergeCommit.oid` before watching
publication. Set `publication_pr` to that PR number and retrieve the value:

```bash
publication_pr='INTENDED_PR_NUMBER'
gh pr view "$publication_pr" --repo hube/devcontainer \
  --json state,mergeCommit \
  --jq 'if .state == "MERGED" and .mergeCommit.oid != null then .mergeCommit.oid else error("Selected PR has no merged commit") end'
```

The command must succeed and print the full SHA. Substitute that SHA below;
an older merge must select its own run,
even when newer main runs exist. This observes a run, without triggering one.

```bash
publication_merge='FULL_MERGE_COMMIT_SHA'
publication_runs=$(mktemp)
gh run list --repo hube/devcontainer --workflow publish.yaml --branch main \
  --commit "$publication_merge" --limit 2 \
  --json databaseId,headSha,headBranch,url > "$publication_runs"
cat "$publication_runs"
```

If the command fails, retain its stdout/stderr; the intended run has not been
selected. Restore the reported GitHub access and repeat the same selection.
Continue only after it succeeds. Validate cardinality and the returned commit
and branch before selecting the run identifier:

```bash
publication_run=$(jq -er --arg sha "$publication_merge" '
  if length == 0 then error("No publication run for the selected merge")
  elif length != 1 then error("Ambiguous publication runs for the selected merge")
  elif .[0].headSha != $sha or .[0].headBranch != "main"
    then error("Publication run commit or branch does not match")
  else .[0].databaseId end
' "$publication_runs")
```

An absent match leaves publication for this merge unobserved: confirm the merge
SHA and inspect the workflow's push trigger and Actions access, then repeat the
selection. Ambiguous matches leave the run choice unresolved: inspect the
returned run URLs and establish which run belongs to the intended publication.
Do not watch a run until the selection is unambiguous.

Read back that run through Actions and verify the workflow path as well as the
commit and branch before watching it:

```bash
publication_identity=$(mktemp)
gh api "repos/hube/devcontainer/actions/runs/$publication_run" \
  > "$publication_identity"
cat "$publication_identity"
jq -e --arg sha "$publication_merge" --argjson run "$publication_run" '
  .id == $run and .head_sha == $sha and .head_branch == "main" and
  .path == ".github/workflows/publish.yaml"
' "$publication_identity"
```

A failed read or a false identity check leaves the run unverified. Retain the
output, correct the selected repository, SHA or workflow from the intended PR
and workflow configuration, and repeat selection and readback. Only after both
commands succeed, watch the verified run:

```bash
gh run watch "$publication_run" --repo hube/devcontainer --exit-status
rm "$publication_runs" "$publication_identity"
```

Do not begin post-publication acceptance unless the workflow exits zero. A
failed workflow means the reviewed commit is not known to be present in the
published tag; inspect the run log, fix or rerun the publication job, and wait
for a successful run.

## Post-publication acceptance

Pull the published tag explicitly so a cached pre-merge image cannot satisfy
the consumer test, then exercise the original image-only consumer path:

```bash
docker pull ghcr.io/hube/devcontainer:latest
bash .devcontainer/local-features/codex/test/test-image-consumer.sh ghcr.io/hube/devcontainer:latest
```

Close issue #36 only after both commands exit zero and the consumer test
reports successful post-create health and sandboxed patch persistence. If the
test fails, the problem is in the published-image consumer path; users may
still be unable to start the image or persist Codex patches. Preserve the full
output, correct the publication or runtime failure, publish again, and repeat
this check before closing the issue.

## Cleanup

The runtime and consumer harnesses remove resources they own and fail when
required cleanup does not succeed. Because the stable local image is supplied
by the maintainer, remove it explicitly after acceptance:

```bash
docker image rm -f codex-runtime-test:acceptance
```

If cleanup fails, the command diagnostic identifies the retained build log,
container, volume, or image. Remove that named resource after restoring Docker
or filesystem access; do not assume a failed harness left no resources behind.

## Retiring runtime relaxations

If the default-security control starts passing, stop publication. The current
`seccomp=unconfined` or `apparmor=unconfined` setting may no longer be needed,
so preserving it would retain unnecessary container-wide exposure. Redesign
the outer runtime contract, rerun the controlled matrix, and update the Feature
metadata and user guidance before publishing.
