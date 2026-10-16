# Incremental Codex autonomous recovery

## Context

The [approved proposal](proposal.md)
defines the execution scope and rigor. This design divides that scope into
usable deliveries rather than separate configuration, instruction, and testing
phases. Each delivery includes the wiring and verification its outcome needs.
The original 35 tasks are complete. The owner's subsequent scope review adds
the [selected integration follow-ups](proposal.md#selected-integration-follow-ups)
without treating their new acceptance as already performed.

## Goals

- Make the first delivery useful to desktop remote agents and delegates starting
  authorized work, without depending on the remaining operation classes.
- Extend the same recovery contract through later deliveries, keeping earlier
  outcomes usable and regression-checked.
- Deliver changes to canonical guidance in hube/claude-home and integration
  acceptance here without maintaining a second instruction corpus.
- Supply executable acceptance recipes and discoverable prerequisites for the
  selected recovery flows, preserving the distinction between disposable probes
  and supported desktop integration acceptance.
- Make installation, check termination, publication integrity and SSH connection
  setup usable through their selected failure cases and consumer lifecycles.

## Non-goals

The proposal's exclusions apply. An initial delivery does not claim complete
coverage of all operations or all existing configurations. No delivery introduces
an approval bypass, ownership registry, or custom command broker.

## Rigor Levels

The proposal's [rigor table](proposal.md#rigor-levels)
is the governing input. Recovery, evidence, and acceptance verification remain
provisional, per the [owner's direction](https://github.com/hube/devcontainer/pull/80#issuecomment-5941606889).
Mechanisms described here are candidates for review, not ratification of those
levels. Agent working-tree content is re-doable; shared registrations, ownership
records, history, committed outputs, and persistent user state remain protected.

Incremental delivery is Decided (owner, 2026-10-01, in session): every work unit
must deliver a useful outcome, and subsequent units build on it.

## Decisions

### First delivery: start an isolated task autonomously

For an authorized task in an already-compatible desktop remote session, an agent
or delegate can create its own branch and linked worktree, recover from an
eligible sandbox denial through automatic approval, and resume work in that
worktree without an owner intervention.

The delivery includes a narrow canonical guidance change, consumption through
existing instruction mounts, and live acceptance on the supported remote
integration. It is complete only when those pieces work together. A document
change or a standalone shell probe is insufficient.

Before selecting a runtime remedy, demonstrate that a real delegate can request
an eligible escalation, receive automatic approval, execute the setup operation,
and continue. This is a feasibility gate inside the first unit, not a separate
claimed functionality delivery. If that path is unavailable, identify its owning
runtime or upstream dependency and revise the first unit around the minimum
integration fix. Do not replace it with manual approval or full access.

A compatible session has the shared guidance available and effective settings
that permit the supported automatic review path. Read the effective session
policy, rather than inferring it from a feature configuration file. Test both
parent and delegate execution. Incompatible settings are diagnosed explicitly;
broader existing-install adoption is a later delivery.

The recovery contract distinguishes an execution sandbox denial from a rejected
approval, a worktree ownership refusal, an authorization failure, and an ordinary
command failure. Only the eligible sandbox denial enters the Codex-specific
approval path. Inspect branch and worktree side effects before a retry; reuse
only this task's valid partial setup. A rejected review or ownership refusal
terminates that recovery path. Generic permission text alone is insufficient to
classify the failure.

Canonical procedures have one home in hube/claude-home. Relevant worktree and
orchestration stop conditions reference that recovery path without permitting
writes in primary checkouts or other tasks' worktrees. The runtime continues to
own the approval decision; guidance supplies the classification and continuation.

### Subsequent deliveries extend one outcome at a time

| Delivery | User-visible outcome | Builds on |
| --- | --- | --- |
| Isolated task startup | Parent and delegate establish their own branch/worktree and continue after eligible sandbox denial | Existing automatic review and shared-guidance mounts, or their minimum required integration fix |
| Obtain task inputs | The agent fetches authorized repository state and continues without routine intervention | Startup and the same failure-classification contract; include SSH transport where the selected fetch path requires it |
| Execute and verify work | The agent runs representative Node subprocess tooling and task checks, recovering eligible execution denials | Isolated workspace and input retrieval |
| Publish a reviewable result | The agent signs its commit and pushes to an authorized destination, then opens or updates the intended review artifact | Earlier operations plus the existing signing and publication integration |
| Adopt across existing installations | Fresh containers and persistent installations expose and adopt necessary effective settings without replacing user configuration, credentials, or session state | A demonstrated recovery contract and the exact settings it requires |

Each delivery carries its own operator guidance, relevant configuration changes,
and acceptance. A configuration fix necessary for an earlier outcome belongs in
that outcome's unit; it is not postponed to the adoption unit. Adoption expands
coverage beyond already-compatible installations rather than making earlier
units deployable for the first time.

The original delivery order follows task execution so each extension consumes
the preceding outcome. Validator liveness is now explicitly selected as a new
delivery below; alias lifecycle remains separate under the proposal's boundary.

### Reproducible documentation and acceptance

The [proposal's selected documentation scope](proposal.md#selected-documentation-scope)
sets the repair boundary. Recovery prerequisites, fixture producers, capture and
comparison inputs, and diagnostic cases belong in this repository's Codex feature
documentation. Repository-check discovery and attribution producers belong in
hube/claude-home, reached by references rather than copied procedures.
Decided (owner, 2026-10-08:
[recovery and canonical selection](https://github.com/hube/devcontainer/issues/96#issuecomment-6074448366)).

Acceptance recipes define the protected subset and intentional task additions.
Their comparison rejects a changed protected baseline while accepting preserved
state and permitted additions. SSH and signing diagnostics select disposable
inputs per invocation; real credentials and global configuration remain protected.
The representative Node check uses a resource restricted by each actor's actual
policy, and retains the actual denial, approved retry and ordinary failed-check
results separately.

Operator prerequisites identify the feature-provided and desktop-provided socket
routes and the official remote authentication authority. A route without a
restoration control names its diagnostic/escalation destination. Adoption recipes
separate synthetic copy-wiring fixtures from live installation state capture;
capture excludes credential contents and accounts for concurrent session writes.

The publication selector binds the named workflow on main to the selected merge
SHA and checks the returned identity before observing its outcome. A missing or
ambiguous match requires diagnosis rather than substituting another run.
Decided (owner, 2026-10-08:
[selector selection](https://github.com/hube/devcontainer/issues/96#issuecomment-6074521646)).

These recipes implement the existing acceptance goals. They do not introduce
standing enforcement, an ownership registry, or a broader supported runtime.
Any net always-on guidance growth requires a concrete owner decision; canonical
producer detail uses an on-demand home where sufficient.

### Restore the existing instruction activation

The owner performs the documented host-source restoration and container
recreation after the scope discussion. Afterward, verify the actual mounted
always-on file and bulk corpus, new parent/delegate consumption, and the existing
configuration, authentication and history boundaries. A directory listing alone
cannot establish restoration. Retain captured failures and the actual verification
result; do not reuse earlier restoration receipts as this run's evidence.

This is verification of the existing restoration procedure. Preventing future
stale single-file binds or redesigning mounts is not selected. Isolated software
work can proceed independently; acceptance requiring restored mounted guidance
remains pending until the owner action and readback succeed.

### Install skills independently for both harnesses

The agent-skills post-start hook invokes the maintained installer once with
`claude` and once with `codex`, retaining its existing clone/ref-refresh behavior
and non-blocking container startup. Attempt both targets even if one fails, and
report the affected target, consequence and installer remedy. Reuse the installer's
state-conflict checks; do not replace user configuration or another marketplace
registration to force success.

Focused tests check our argument and failure-aggregation wiring against the
actual installer contract, naming any CLI stubs. Normal fresh, existing and
repeated installations supply separate installed-state readback for both harnesses.
The programme's payload repair #156 is a prerequisite already delivered at its
own boundary, not another implementation of this caller fix. Feature NOTES owns
the changed startup behavior; agent-skills #114/#39 links that source.

### Bound attribution validation without weakening it

Use the existing trailer-parser subprocess boundary with a finite deadline and
termination of its task-owned child. Separate timeout from missing executable
and ordinary nonzero exit in the diagnosis. Timeout remains unsuccessful
validation in every mode and rejects a hook-invoked commit. Its remedy identifies
the failed validation and supported recovery; it must not suggest that the
message was checked or that attribution can be omitted.

A controlled hanging child and an outer test watchdog prove bounded return and
our diagnostic, including a failing control without the fix. Normal parsing and
other error paths remain covered. Verify the affected sandbox invocation and its
exact supported approved continuation separately; do not infer a kernel-policy
fix from a timeout fixture. Rebuild the committed bundle and use the repository's
existing byte-comparison gate. No new attribution-presence or identity policy is
introduced by sharing this implementation boundary with #69/#73.

### Supply a corrected jq image input

Pin the official jq 1.8.2 release, which contains the
[raw-input slurping fix](https://github.com/jqlang/jq/pull/3421), in a feature-owned
image installation input. Verify release artifacts and digests for the published
image architecture, retain the package-owned binary, and ensure the corrected
binary is selected earlier on the effective PATH. This corrects an existing
runtime tool; it does not introduce a new runtime service.

Verify our selected version, artifact and PATH wiring with focused controls.
Then exercise the effective image binary using a self-contained multibyte-boundary
fixture and a representative large payload through stdin and file arguments.
Decode the resulting JSON and compare the text exactly; exit zero alone is not
acceptance. A known-affected binary must reject that equality assertion, and a
working control must pass. Keep publication body readback in the supported flow;
no dependency on private historical fixture contents or tests of jq internals is
introduced. Document activation through image rebuild/adoption and the existing
safe payload route while an installation is still affected.

### Allocate SSH ports natively and refresh a stable alias

Use a string `appPort` mapping such as `127.0.0.1::2222`: Docker chooses the host
port while the container listener remains 2222. The
[Dev Containers CLI](https://github.com/devcontainers/cli/blob/main/src/spec-node/singleContainer.ts)
passes string entries to Docker unchanged; an integer instead requests a fixed
mapping. Native allocation removes the manual port search without a custom
allocator or a check-then-bind race.

Provide a host-side connection helper in this repository, invoked by the
documented create/recreate entry path on the Docker Desktop host. Use the
container identity returned by that lifecycle and verify its selected consuming
workspace before inspecting its actual loopback mapping. Diagnose missing,
ambiguous or stale identity/mapping inputs rather than selecting another running
container. Report underlying Docker and SSH failures with their actual results.

Maintain a generated SSH configuration fragment for the consumer's stable,
concrete alias. Integrate it through an explicit host SSH include, preserve
unrelated configuration, and refuse conflicting user-owned aliases or fragments.
Refresh only that managed entry after successful discovery on creation/recreation;
do not require manual port editing. Keep normal SSH authentication and host-key
verification. Trust failures need their normal diagnosis rather than disabling
checks or replacing credentials. The helper is an invoked host tool, not a
container process editing host configuration or a standing service.

Docker mapping readback establishes allocation only. Verify two simultaneous
consumers while the conventional host port is occupied, correct alias-to-consumer
selection, and recreation with a changed mapping. Then prove SSH and actual
supported desktop reconnection using those aliases. Official
[remote-connection guidance](https://learn.chatgpt.com/docs/remote-connections#connect-to-an-ssh-host)
establishes concrete SSH aliases as the client input; it does not establish hot
reload or reconnection after a changed mapping. Preserve other listeners, aliases,
user state and the unrelated consumer throughout this acceptance.

### Deliver three documentation groups at their owning homes

**Host onboarding.** README identifies the consuming project and makes startup
and shell entry target the same workspace, distinguishing image consumption from
developing this repository. Claude feature NOTES supplies missing host projects-
directory preparation, preserving existing bytes and diagnosing wrong-type paths.
Explain persistence from the actual consumer mounts: host binds and named volumes
retain their existing behavior; unmounted sibling directories remain disposable.
Locate required recreation backups/notes on existing persistent storage. Reference
the automatic SSH connection delivery instead of retaining contradictory static
port examples. Verify the route in a disposable consumer and link its owning
source from agent-skills #39 through that programme's own delivery.

**GitHub authentication.** GitHub CLI feature NOTES supplies the host-variable and
remoteEnv example or exact configuration reference, keeps GH_TOKEN precedence,
and provides remote authentication readback. Keep this distinct from SSH Git
transport. Resolve the selected consumer's actual mounted GitHub CLI volume
read-only before the existing removal procedure; diagnose missing/ambiguous
targets and prove discrimination against a decoy. Retain the logout alternative.
Synthetic token-input tests name their authentication stubs; live readback
establishes the existing authorized account without exposing or deleting real
credentials.

**Runtime terminology.** Define control, treatment, omission, restoration and final
result labels at the Codex maintainer acceptance entry, including how the wrapper
proves selection of system Bubblewrap. Compare definitions with the maintained
script; operator NOTES links to that explanation. This group does not change
runtime settings, backend support or the existing matrix execution policy.

Each group carries its own focused verification and required reader review.
Canonical procedures remain in their owning corpus; do not add duplicate
agent-skills setup documentation or change that programme's sequence here.

### Alternatives

**Change all configuration first.** Rejected: the feature already selects an
automatic reviewer, and a configuration file does not establish effective policy
or delegated continuation. It can expand migration scope before identifying the
setting a useful workflow actually needs.

**Deliver guidance, infrastructure, and acceptance as separate units.** Rejected:
none establishes an agent outcome alone; the benefit arrives only after the last
layer lands. Those pieces may have separate repository PRs, but jointly form one
functional delivery.

**Deliver all Git, SSH, Node, adoption, and publication support together.**
Rejected: the first useful improvement then depends on every operation class.
A startup slice provides value while the remaining integrations are delivered.

**Archive the original scope before its selected follow-ups.** Not selected: the
owner keeps one change open for the expanded recovery outcome. Preserve the
completed tasks and add pending deliveries, then finalize after their acceptance.

**Document manual port choice only.** Superseded by the owner's automatic-
allocation decision. Docker already supplies allocation; reliable discovery and
the SSH configuration lifecycle are the additional integration work.

## Acceptance and Rollout

The first delivery owes a representative live parent/delegate scenario showing
sandbox denial, approved escalation, successful setup, and subsequent work in the
created worktree. The scenario must establish that the denial and approval paths
were exercised; a command that never needed escalation proves only the success
path. Include rejected approval and ownership-refusal cases that do not retry
through a bypass, and an ordinary command failure that is not misclassified.

Use disposable task repositories for these probes. Compare shared registrations
and refs before and after to detect unintended mutation. Tests in this repository
verify our configuration, wiring, and guidance inputs; live probes establish the
third-party runtime behavior. Neither substitutes for the other.

Land the canonical guidance and any required integration change through their
respective repository review gates. Treat the unit as available only after the
supported mounted guidance and runtime consume those changes together. Existing
compatible sessions may need to refresh their instruction context; the unit's
operator guidance must describe that activation step. Rollback restores the
changed guidance/configuration without clearing user state or other worktrees.

Each original runtime extension repeats the earlier supported scenarios and adds
its new one.
It must identify its supported configuration subset and any remaining limitation;
it must not claim closure of issues whose full acceptance criteria are unmet.

The selected documentation repairs use the
[disposition inventory's verification obligations](https://github.com/hube/devcontainer/issues/96#issuecomment-6044021452),
implemented by [tasks 6–9](tasks.md#6-deliver-reproducible-recovery-documentation).
Run the revised disposable recipes with their failure controls and separately
exercise the specified supported host/client and parent/delegate paths. A static
review or prior receipt does not discharge a newly documented live procedure.
Unavailable host/client verification remains an explicit unmet criterion.

The expanded deliveries in tasks 10–18 preserve those prior completion records.
Each functional repair includes its own input controls, effective runtime
readback, operator guidance and integration acceptance. Rerun earlier cases
affected by that repair; final reconciliation combines the consumed outcomes
rather than deferring their first verification to the end. Update owning issue
criteria against the selected outcomes before claiming closure, including #43's
now-explicit automatic connection setup. Specification synchronization and
archiving follow completion of the expanded scope as separate finalization work.

Canonical guidance and its consumers land through their owning repository gates.
Instruction-authoring adherence and the required reader-proxy reviews apply to
the repaired guidance. Related-criteria navigation follows the proposal's stated
owner overrides for issues 74–76; their original non-elevated outcomes are not
additional repair requirements. Spec synchronization and archiving follow repair
verification and reconciliation as separately authorized finalization work.

## Risks / Trade-offs

- Effective policy or delegate approval may differ from feature defaults. The
  delegated feasibility gate establishes the supported path before a remedy is
  selected; failure changes the integration dependency, not the approval policy.
- Early delivery supports a narrower configuration subset. Explicit preconditions
  keep that benefit usable while later adoption extends installation coverage.
- Cross-repository changes can land at different times. Activation acceptance
  binds the consumed guidance and runtime together before announcing availability.
- A retry can encounter partial setup. Inspect task-owned side effects and
  continue or stop without modifying another task's registered state.
- Port discovery can become stale after recreation. Bind it to the intended
  lifecycle result, refresh the managed alias, and verify actual reconnection.
- A timeout or successful JSON-producing command can hide an unsuccessful
  outcome. Verify bounded termination and exact content independently of status.
- Host helpers can encounter user-owned SSH settings. Limit writes to the managed
  fragment and explicit include; report conflicts without taking over aliases.

## Supporting Evidence

Supporting evidence; not part of the design; held to the same durability
standards as the body.

The repository's [feature defaults](../../../.devcontainer/local-features/codex/home/.codex/config.toml)
select `approvals_reviewer = "auto_review"`. This supports evaluating effective
runtime policy and guidance before adding another default; it does not prove
that the desktop or a delegate uses the required approval path.

## Changelog

- Owner scope review: Added verified restoration, installer #84, validator #67,
  publication integrity #72, automatic SSH connection setup #43 and the selected
  onboarding, authentication and runtime terminology deliveries. Preserved prior
  acceptance and deferred finalization until the expanded scope is complete.
- 2026-10-08: Added the owner-selected recovery documentation, canonical
  prerequisite and publication-selector scope, with reproducibility and live
  verification boundaries.
- 2026-10-01: Initial design for incremental delivery following the approved
  proposal and the owner's request for useful end-to-end work units.
