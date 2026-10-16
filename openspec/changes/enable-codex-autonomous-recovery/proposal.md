# Proposal

## Why

Codex agents performing ordinary development work in this devcontainer encounter
sandbox denials that interrupt Git setup, SSH operations, and Node tooling;
blanket permission-failure stop conditions prevent supported automatic recovery.
Enable desktop remote agents and their delegates to complete routine authorized
work with minimal human intervention while protecting committed outputs,
persistent user state, and shared repository state.

## What Changes

- Support Codex's existing automatic approval review for eligible sandbox
  escalations. Automatic escalation is an acceptable execution path; completing
  every operation without elevation is not a delivery requirement. Approval
  rejection remains binding, with only materially safer alternatives permitted.
- Coordinate a canonical shared-instruction change in
  [hube/claude-home](https://github.com/hube/claude-home). Failure classification
  is harness-neutral; the supported approval mechanism is explicit for Codex.
  Cover orchestration and worktree creation without duplicating the instruction
  corpus in this repository.
- Distinguish sandbox denial, genuine authorization failure, and ordinary
  command failure. Permit safe recovery in the same seat, inspect partial
  effects before retrying, and preserve actionable progress when recovery
  cannot continue. Working in a primary checkout or another task's worktree is
  not a recovery path.
- Cover both fresh containers and existing installations with persistent Codex
  state. Verify effective permissions and approval settings; adopt any necessary
  changes without silently replacing user configuration, authentication, or
  session history. Identify incompatible managed or user settings explicitly.
- Add representative acceptance for desktop remote sessions and actual delegated
  execution: Git worktree/branch setup, fetch, tests, Node subprocess tooling,
  SSH signing, and publication to an authorized test destination. Verify
  concurrent seats use distinct worktrees and branches without damaging
  protected work. Standalone CLI execution is a diagnostic baseline, not an
  additional supported-client commitment.
- Establish delegated automatic approval and continuation as the initial
  feasibility check. A manually elevated command or a successful shell sandbox
  probe alone does not establish delegated autonomous completion. If the remote
  runtime cannot provide the supported approval path, identify the owning
  integration or upstream dependency before committing to a workaround.
- Make the selected operator prerequisites and acceptance recipes reproducible,
  including disposable fixtures, protected-state comparisons, actual denial
  inputs, and adoption readback. Keep canonical check and attribution producers
  in hube/claude-home, and select publication runs by the intended merge.
- Complete the selected integration follow-ups: independent Claude and Codex
  skills installation, bounded attribution validation, Unicode-preserving JSON
  publication, and automatic SSH port allocation with usable connection settings
  after container recreation.
- Finish host onboarding, GitHub authentication and runtime acceptance guidance,
  and verify the owner's restoration of the existing instruction mount.

### Selected documentation scope

The [disposition author's inventory](https://github.com/hube/devcontainer/issues/96#issuecomment-6044021452)
defines the bounded repairs and verification for the
[owner-selected recovery and canonical scope](https://github.com/hube/devcontainer/issues/96#issuecomment-6074448366).
Decided (owner, 2026-10-08:
[selection](https://github.com/hube/devcontainer/issues/96#issuecomment-6074448366)).

- In this repository's Codex NOTES.md: forwarding restoration routes and the
  remote Codex authentication prerequisite.
- In Codex MAINTAINERS.md: fixture preparation and protected baseline;
  preservation comparator and changed-baseline control; startup classification
  inputs; OpenSpec prerequisite; isolated transport/signing diagnostics; real
  Node-check denial; disposable configuration copying; adoption capture/readback;
  and related-criteria navigation.
- In hube/claude-home's canonical check and attribution guidance: repository-check
  discovery, Codex session identifier production, and model display-name
  resolution, using harness-specific branches where their mechanisms differ.

The publication-run correction in Codex MAINTAINERS.md selects the intended
merge's workflow run rather than the latest unrelated run. Decided (owner,
2026-10-08:
[separate selector selection](https://github.com/hube/devcontainer/issues/96#issuecomment-6074521646)).

Tasks 6–9 cover recovery documentation and canonical prerequisites. Host workspace,
host projects-directory, runtime terminology, token-wiring and credential-volume
repairs are included in the integration scope below. The inventory's merits
declines remain outside scope. Canonical procedures retain one home; proposed
net always-on growth requires a concrete owner decision.

### Selected integration follow-ups

Decided (owner, in this change's scope review): the following outcomes belong
to this change. Each task requires its own acceptance evidence.

| Delivery | Selected outcome |
| --- | --- |
| Instruction restoration | The owner restores the existing host instruction source after the discussion; verify readable guidance consumed by a fresh parent and delegate and preservation of persistent state. Preventive mount redesign is outside this decision. |
| [Installer #84](https://github.com/hube/devcontainer/issues/84) | Startup explicitly installs for both Claude and Codex, attempts each independently, diagnoses each failure and preserves user-owned state on fresh and repeated setup. |
| [Validator #67](https://github.com/hube/devcontainer/issues/67) | Bound trailer-parser waits. Timeout is unsuccessful validation and rejects a hook-invoked commit with an actionable diagnosis, retaining supported recovery and attribution requirements. |
| [Publication integrity #72](https://github.com/hube/devcontainer/issues/72) | Supply a corrected jq image input and verify exact Unicode preservation in the supported JSON publication path. |
| [SSH connection setup #43](https://github.com/hube/devcontainer/issues/43) | Use native automatic localhost port allocation, reliably discover the intended container's mapping, and maintain a stable SSH alias across creation and recreation, with actual desktop reconnection acceptance. |
| Host onboarding | Repair explicit consuming-workspace selection and required host projects-directory preparation; explain [rebuild persistence #30](https://github.com/hube/devcontainer/issues/30) using the existing mount/persistence model. |
| GitHub authentication | Supply host-token and remoteEnv wiring, authentication readback, and exact credential-volume identification with missing/ambiguous-target diagnosis. Verification requires no real credential deletion. |
| Runtime terminology | Define matrix cases, result labels and system-Bubblewrap instrumentation at the maintainer home and link operator guidance to it. |

The four functional repairs are separate deliveries with their own guidance and
verification. The three documentation groups retain their owning feature homes.
Automatic SSH allocation and connection refresh form #43's functional delivery;
onboarding guidance consumes that connection path.

Coordinate setup references with
[agent-skills #114](https://github.com/hube/agent-skills/issues/114) and
[#39](https://github.com/hube/agent-skills/issues/39). This repository owns the
bootstrap and feature procedures; that programme consumes them under its existing
scope and sequence. Installer payload copying is owned by
[#156](https://github.com/hube/agent-skills/issues/156); #84 owns the startup
caller's explicit harness selection and independent attempts.
Its attribution fallback work retains its own unit and canonical authority.
Specification synchronization and archiving follow delivery acceptance and
criterion reconciliation.

Private Git administration, a custom command broker, blanket full access,
additional Codex client support, and eliminating all upstream sandbox defects
remain outside scope. Alias lifecycle #77 stays separate unless a concrete
supported-flow blocker is established. Durability guarantees for unmounted
sibling directories, a custom port allocator, a standing service, general
dependency upgrades, attribution-enforcement policy, signing redesign and
test-infrastructure redesign are outside scope.

## Rigor Levels

These levels cap the machinery needed for this delivery. Settled scope choices
are owner inputs. Provisional tolerances guide mechanism exploration without
ratifying the levels or authorizing implementation. Existing data-integrity and
ownership protections remain binding regardless of provisional levels.

Humans use separate workspaces and repositories from those mounted in this
devcontainer; no human-authored work is present in its checkouts. Decided
(owner, 2026-10-01: [environment scope](https://github.com/hube/devcontainer/pull/80#discussion_r4160936197)).
The [worktree isolation design](https://github.com/hube/claude-home/blob/main/docs/designs/2026-08-25-worktree-isolation-design.md#rigor-levels)
separates re-doable agent working-tree contents from protected shared repository
state. That classification depends on separate human clones and push-as-you-go
with immediate escalation of push failures; if either prerequisite fails, the
working-tree protection level reverts to the stronger integrity floor.

Recovery, evidence, and acceptance-verification tolerances remain provisional
while their supporting mechanisms are explored. Decided (owner, 2026-10-01:
[calibration direction](https://github.com/hube/devcontainer/pull/80#issuecomment-5941606889)).

| Area | Required outcome and limit | Status |
| --- | --- | --- |
| Routine execution | Authorized desktop remote agents and delegates can use supported automatic approval and recovery without routine owner prompts. Non-elevated execution and private Git administration are not required outcomes. | Decided (owner, 2026-10-01, in session) |
| Working-tree isolation | Agent uncommitted work is re-doable at the cost of rework. Machinery is capped at concise prose and checks piggybacked on existing events. Approval does not authorize using another session's worktree or a primary checkout. | Inherited owner decision; [worktree design](https://github.com/hube/claude-home/blob/main/docs/designs/2026-08-25-worktree-isolation-design.md#rigor-levels) |
| Shared repository state | Protect committed outputs, persistent user state, other sessions' worktree registrations and ownership records, and shared history. Never remove, repoint, or rewrite shared state the agent did not create. Mechanical verification is authorized; adversarial containment of an approved command is not an added guarantee. | Governing protection floor; [worktree design](https://github.com/hube/claude-home/blob/main/docs/designs/2026-08-25-worktree-isolation-design.md#rigor-levels) |
| Ownership and audit records | Worktree-purpose reconstruction is a cost of owner effort. Concise prose is sufficient; no standing ownership contract is required. Existing ownership records remain protected as shared state. | Inherited owner decision; [worktree design](https://github.com/hube/claude-home/blob/main/docs/designs/2026-08-25-worktree-isolation-design.md#rigor-levels) |
| Failure recovery | Re-doable: the agent's disposable partial work may be discarded and rerun without damaging protected state. Inspect side effects before retrying; recovery is bounded and respects rejected approvals. Crash-proof preservation of all in-progress work is not required. | provisional (author-proposed) |
| Evidence and handoff | Record enough verified context to diagnose a terminal failure and resume the task. Per-command durable journals and independently reconstructable audit trails are not required. | provisional (author-proposed) |
| Acceptance verification | Mechanically check representative delegated operations, concurrent work, and configuration adoption when delivering or changing the supported integration. Checks demonstrate their target was exercised. Independent verification on every task and a new standing process-enforcement service are not required. | provisional (author-proposed) |
| Compatibility and adoption | Cover fresh and existing devcontainers for desktop remote sessions and delegates, preserving persistent user state. Standalone CLI is a diagnostic baseline; other clients and universal upstream-defect elimination are outside this delivery. | Decided (owner, 2026-10-01, in session) |

The [shared rigor discipline](https://github.com/hube/claude-home/blob/main/instructions/rigor-levels.md)
governs calibration. Stronger protection, audit, or verification machinery needs
an explicit owner requirement rather than accumulation through review findings.

### Mechanisms to Explore

These candidates support the declared outcomes without raising provisional
levels. Their suitability depends on the delegated feasibility check and the
later design; they are not implementation commitments.

| Outcome | Candidate mechanism | Rigor limit |
| --- | --- | --- |
| Autonomous execution and recovery | A canonical failure-classification and recovery branch uses supported automatic approval, checks partial effects, and bounds retries. | Concise agent guidance and existing runtime approval facilities; no custom broker or crash-preservation protocol. |
| Working-tree isolation and shared-state protection | Reuse existing worktree creation and ownership rules, with focused checks on shared-state mutations. | Uncommitted agent content remains re-doable; registration and history protection may use mechanical verification without a new ownership registry. |
| Evidence and handoff | Use existing commits, push-as-you-go, and a concise diagnostic handoff for terminal failures. | Actionable evidence for resumption; no per-command journal or independently reconstructable audit service. |
| Configuration adoption | Inspect effective settings and apply only necessary, explicit changes through the feature's adoption path. | Preserve user configuration and persistent state; no replacement of the full configuration tree. |
| Acceptance verification | Add representative desktop/delegate scenarios to delivery checks and demonstrate that each check exercises its target. | Verify the supported integration when it changes; no independent verifier on every agent task. |

## Capabilities

### New Capabilities

- `codex-agent-recovery`: Desktop remote agents and delegates complete routine
  authorized operations through supported automatic approval and safe recovery,
  preserve protected work, and escalate actionable failures when recovery is
  unavailable or authorization is unresolved. Checks terminate with useful
  diagnoses, publication preserves Unicode, and authentication and acceptance
  prerequisites are reproducible.
- `codex-runtime-adoption`: Fresh and existing devcontainer installations expose
  verifiable effective Codex execution settings and an adoption path that
  preserves user configuration and persistent state, with restored guidance,
  independent skills setup for both harnesses, reproducible host onboarding and
  automatic SSH connection setup across recreation.

### Modified Capabilities

None.

## Impact

Affected areas include the Codex and agent-skills feature wiring, attribution
validator and committed bundle, effective jq image input, host-side SSH connection
helper, consumer configuration, and README and owning feature guidance. Existing
runtime tools are corrected or reused; no new service is proposed. Host SSH
configuration changes must be limited to the selected consumer's managed entry,
preserving unrelated settings. Canonical instruction changes belong to
hube/claude-home and retain that repository's review gate. This proposal changes
no runtime behavior itself.

For [Git-state issue #74](https://github.com/hube/devcontainer/issues/74),
[Node subprocess issue #75](https://github.com/hube/devcontainer/issues/75), and
[SSH issue #76](https://github.com/hube/devcontainer/issues/76), issue maintainer
01a11490 records owner-directed not-planned dispositions:
[Git state](https://github.com/hube/devcontainer/issues/74#issuecomment-6030966274),
[Node](https://github.com/hube/devcontainer/issues/75#issuecomment-6030967807), and
[SSH](https://github.com/hube/devcontainer/issues/76#issuecomment-6030968321).
Citing those recorded dispositions: the owner's rulings override the issues'
original non-elevated closure criteria. Automatic recovery acceptance does not
establish those original criteria as implemented.
Issues #84, #67, #72, #30 and #43 require criterion-by-criterion reconciliation
against their selected outcomes; merge alone does not close them. Issue #43's
automatic-allocation and connection-lifecycle outcome is defined above. The
host onboarding, authentication and runtime terminology defects in issue #96
are in scope; its merits declines remain separate. [Alias issue #77](https://github.com/hube/devcontainer/issues/77)
retains independent closure criteria. Broader gate enforcement (#69/#73), signing
extraction/design (#32/#71), test infrastructure (#62), XDG migration (#29), naming
conventions (#34) and unproven shell-prompt work (#12) are not admitted here.
