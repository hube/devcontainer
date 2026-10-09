Plan author - 01a11f37

# Incremental Codex autonomous recovery

## Context

The [approved proposal](proposal.md)
defines the execution scope and rigor. This design divides that scope into
usable deliveries rather than separate configuration, instruction, and testing
phases. Each delivery includes the wiring and verification its outcome needs.

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

The order follows task execution so each extension consumes the preceding
outcome. Independent validator liveness and alias lifecycle work remain outside
this chain unless a concrete dependency blocks an outcome.

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

Every later unit repeats the earlier supported scenarios and adds its new one.
It must identify its supported configuration subset and any remaining limitation;
it must not claim closure of issues whose full acceptance criteria are unmet.

The selected documentation repairs use the
[disposition inventory's verification obligations](https://github.com/hube/devcontainer/issues/96#issuecomment-6044021452),
implemented by [tasks 6–9](tasks.md#6-deliver-reproducible-recovery-documentation).
Run the revised disposable recipes with their failure controls and separately
exercise the specified supported host/client and parent/delegate paths. A static
review or prior receipt does not discharge a newly documented live procedure.
Unavailable host/client verification remains an explicit unmet criterion.

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

## Supporting Evidence

Supporting evidence; not part of the design; held to the same durability
standards as the body.

The repository's [feature defaults](../../../.devcontainer/local-features/codex/home/.codex/config.toml)
select `approvals_reviewer = "auto_review"`. This supports evaluating effective
runtime policy and guidance before adding another default; it does not prove
that the desktop or a delegate uses the required approval path.

## Changelog

- 2026-10-08: Added the owner-selected recovery documentation, canonical
  prerequisite and publication-selector scope, with reproducibility and live
  verification boundaries.
- 2026-10-01: Initial design for incremental delivery following the approved
  proposal and the owner's request for useful end-to-end work units.

```text
Harness: Codex
Harness-Version: 0.162.0
Model: GPT-6
Skills: openspec-update-change
```
