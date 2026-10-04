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
`NOTES.md`. Authorize the parent to create a disposable bare repository and
seed commit, a protected fixture worktree, and separate parent/delegate branches
and linked worktrees. Choose a new acceptance directory outside both seats'
effective writable roots that the configured container user can write when
approved; use no production repository. Record that directory in working notes
outside repositories. Include an ignored `.worktrees/` root in the fixture seed.
The parent prepares the fixture through supported approval, then captures its
refs and worktree registrations with these commands, substituting the bare
repository path for `REPO`:

```bash
git --git-dir="$REPO" show-ref
git --git-dir="$REPO" worktree list --porcelain
```

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
const cases = {
  good: ['node', ['-e', 'process.stdout.write("fixture child ran\\n")']],
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

From that same worktree, run `node node-check.cjs good` with default policy.
Run `node node-check.cjs broken` and `node node-check.cjs missing` separately,
retaining each invocation's exit status and complete output. The fixture
retains attached errors instead of normalizing them away. Only an eligible
sandbox denial reaches an approved retry of the identical invocation; an
ordinary missing executable does not. After recovery, require the good
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

## Publication

Merging to `main` triggers
[`.github/workflows/publish.yaml`](../../../.github/workflows/publish.yaml),
which builds and pushes `ghcr.io/hube/devcontainer:latest`. Identify the run
created by the merge and wait for it to finish:

```bash
gh run list --workflow publish.yaml --branch main --limit 1
gh run watch <run-id> --exit-status
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
