# Codex Autonomous Recovery — Delivery Plan

## Goal

Deliver the remaining integration, activation and documentation outcomes in
[`enable-codex-autonomous-recovery`](../../openspec/changes/enable-codex-autonomous-recovery/proposal.md).
Supported desktop remote agents and delegates must be able to complete authorized
work, recover eligible sandbox failures, publish intact attributed output and
reconnect to the intended consumer while preserving protected state.

The original 35 tasks are delivered history. This programme delivers the 24
remaining tasks in groups 10–18; it does not convert previous evidence into new
verification or reopen completed work without a demonstrated regression.

## Charter

### Execution structure

Use GitHub's native issue hierarchy. One new programme ledger owns the live
unit index. Standalone units are its direct sub-issues. The onboarding vehicle
delivers three child work issues in one independently reviewed PR; its own
acceptance criteria reference only those children. No child commit order is
ruled. Native blocking edges represent dispatch prerequisites, not commit order.

- **Ledger-to-units hierarchy:** the programme ledger's native sub-issue graph.
- **Acceptance criteria per unit:** the unit or vehicle issue body, mapped to
  the OpenSpec tasks and capability requirements below.
- **Sequencing discipline:** dispatch only an unblocked unit with current
  criteria, settled scope/remedy/design obligations and both role contexts,
  under the canonical orchestration protocol's “Dispatch readiness”. Preferred
  completion order is given below; the owner may change it.

The delivery plan owns structure. The OpenSpec proposal, design and capability
specifications own the selected behavior contract; its tasks remain the
implementation checklist. The GitHub ledger owns live programme state, and PRs
and no-PR acceptance reports own verification evidence. Keep task marks and
unit closures consistent by reconciling the actual outcomes at harvest.

### Tracking substrate

GitHub issues, native sub-issues and native blocked-by relationships in
`hube/devcontainer`. Reuse issues #72, #84, #67, #43 and #30 rather than creating
duplicate repairs. Issue #96 remains the source inventory and reconciliation
surface; it is not an extra delivery unit or a parent vehicle for separate PRs.
No GitHub Project or parallel board is maintained by this programme.

The programme ledger body is maintained by the current boundary orchestrator
alone, as reserved by `~/.agents/instructions/orchestration-protocol.md`, “The
programme progress ledger”. Its transition comments remain with their authors.
The candidate register is created only when the first process candidate needs
one, following that protocol's “The candidate register”.

### Unit directory name

Role context lives outside repositories in the common checkout parent's
`.delivery-programme-context/devcontainer/` directory, under the directory named
for the programme's GitHub ledger issue. Dispatched units use `NN-<slug>`, assigned
at author-dispatch preparation and never renumbered afterward. An onboarding
vehicle gets one context pair for its one PR. A no-PR unit gets its own pair.

The boundary orchestrator's single `orchestrator.progress-ledger.md` lives at
the programme context root. Author/reviewer context and progress-ledger names,
privacy, creation preflight and read receipts follow the canonical protocol's
“The context ledgers”. Create both dispatch contexts only when the owner is
about to dispatch that unit's author. Bootstrap creates no queued role files.

### Phase shape

The expanded OpenSpec design and this charter land before product delivery.
Each functional unit then supplies its own operator guidance before the behavior
it describes, implementation, meaningful controls, normal integration acceptance
and final guidance reconciliation in its own reviewed PR. No additional standalone
design document is planned for those units under the selected OpenSpec approach;
an author-originated architectural change requires the owning design decision
before its implementation under the canonical PR workflow.

The restoration unit is deliberately no-PR: the owner performs the existing
documented restoration; dispatched author/reviewer seats verify and report its
actual outcome on that issue. Documentation units need no invented code phase.
Final reconciliation establishes combined consumption and criterion closure;
it does not postpone the earlier units' first verification until the end.

Owner merge and role dispatch remain governed by the canonical orchestration
protocol. Programme-specific practices adopted by agent-skills #110 are not
implicitly adopted here.

### Exclusions and scope fences

- Alias lifecycle #77 remains separate unless a supported-flow blocker is
  established and the owner admits the resulting work.
- Preserve the not-planned dispositions of #74–76 and the OpenSpec proposal's
  exclusions, including broader attribution enforcement, signing redesign,
  test-infrastructure machinery, XDG migration and unrelated naming changes.
- Restore the instruction mount through the existing procedure. Preventive
  mount redesign, new sibling-directory durability, a custom port allocator and
  a standing service are not selected outcomes.
- Keep real credentials, unrelated host SSH settings/listeners, shared refs and
  registrations protected. The credential-volume documentation verification
  requires selection evidence, not deletion of real authentication state.
- Keep agent-skills #114/#39's delivery and sequence under that programme's
  ownership. Supply references to the feature procedures this programme owns.
- Spec synchronization and archiving remain subsequent, separately authorized
  finalization after the expanded delivery is complete. Programme bootstrap
  neither implements the repairs nor closes their issues.

### Identity line format

Published programme artifacts begin with:

```text
Codex Recovery 1 <repo-qualified artifact> <model display label> <role> - <session id8>
```

`Codex Recovery 1` is the programme tag. The artifact reference identifies its
issue or PR; the role is orchestrator, author, reviewer or programme designer.
Commits use the canonical attribution trailers instead. Reader proxies publish
through their designated reviewer under the canonical review protocol.

### Decisions in force at charter time

The owner selected the expanded outcomes in this chat and authorized incorporating
the updated OpenSpec plan into a new programme. The reviewed OpenSpec proposal's
[selected follow-ups](../../openspec/changes/enable-codex-autonomous-recovery/proposal.md#selected-integration-follow-ups)
records those bootstrap scope decisions; they are not inferred from issue labels.

- Instruction restoration is owner-performed after the discussion; verified
  restoration is sufficient.
- Startup skills installation covers Claude and Codex independently.
- A validator timeout is unsuccessful validation and rejects a hook-invoked
  commit with an actionable diagnosis.
- Publication integrity includes the affected jq image input and exact Unicode
  preservation.
- SSH setup includes native automatic localhost allocation, actual discovery,
  stable alias refresh and supported desktop reconnection after recreation.
- Onboarding retains the existing persistence model. Authentication and runtime
  terminology remain separate documentation deliveries.

Decisions made after bootstrap belong in the live programme ledger, with links
to the owner's decision records, rather than accumulating in role contexts.

## Governing rigor

Inherit the OpenSpec proposal's
[rigor levels](../../openspec/changes/enable-codex-autonomous-recovery/proposal.md#rigor-levels)
with their existing decided/provisional statuses. Programme creation does not
ratify provisional levels or authorize stronger machinery. Protected state stays
protected; other partial task state remains re-doable under those prerequisites.
Repository controls establish our wiring; real supported host/client acceptance
establishes integration behavior. Neither replaces the other.

## Delivery structure and OpenSpec coverage

| Unit | Work issue / boundary | OpenSpec tasks | Outcome |
| --- | --- | --- | --- |
| Restoration verification | New no-PR unit | 10.1 | Owner-restored guidance is readable and consumed, with persistent-state readback. |
| Publication integrity | Existing #72; separate PR | 13.1–13.3 | Corrected effective jq input preserves the complete Unicode payload. |
| Skills startup | Existing #84; separate PR | 11.1–11.3 | Both harnesses are configured independently, preserving unrelated state. |
| Validator liveness | Existing #67; separate PR | 12.1–12.3 | Parsing terminates within its bound and failure remains actionable. |
| Automatic SSH setup | Existing #43; separate PR | 14.1–14.4 | Native allocation and stable aliases reach the intended consumer across recreation. |
| Host onboarding | New vehicle: workspace selection, projects-directory preparation and existing #30 | 15.1–15.3 | One coherent entry path describes prerequisites and actual persistence. |
| GitHub authentication | New documentation unit | 16.1–16.3 | Token wiring, remote status and exact credential-volume selection are reproducible. |
| Runtime terminology | New documentation unit | 17.1–17.2 | Matrix labels and instrumentation evidence are interpretable. |
| Combined reconciliation | New no-PR unit | 18.1–18.2 | Selected outcomes are consumed together and every issue criterion is reconciled. |

The onboarding vehicle's workspace and projects-directory child issues cover
task 15.1; #30 covers task 15.2. Task 15.3 is their shared entry-path and reader
acceptance within the vehicle. This overlap is deliberate integration coverage,
not multiple assignments of implementation. Final task 18 verification spans
units but does not imply another implementation PR.

## Initial delivery sequence

Default order reflects consequence and dependencies, not task numbering. These
are bootstrap priorities, subject to owner override:

| Preferred order | Unit | Priority and consequence | Dispatch prerequisites |
| --- | --- | --- | --- |
| Independent owner track | Restoration verification | P2: activation is unavailable until restored | Owner action before live restoration evidence; no product-code dependency |
| 1 | #72 publication integrity | P1: successful tooling can silently corrupt published text | None beyond programme dispatch readiness |
| 2 | #84 skills startup | P2: normal startup skips installation | None beyond programme dispatch readiness |
| 3 | #67 validator liveness | P2: a check can stall, with supported approved execution available | None beyond programme dispatch readiness |
| 4 | #43 automatic SSH setup | P2: manual port collisions impede connection setup | None beyond programme dispatch readiness |
| 5 | Host onboarding vehicle | P2: entry prerequisites and rebuild behavior are unclear | #43 closed; the vehicle exercises its delivered connection path |
| Independent documentation | GitHub authentication | P2: account/volume recovery inputs are incomplete | None beyond programme dispatch readiness |
| Independent documentation | Runtime terminology | P2: acceptance evidence cannot be interpreted from the guide | None beyond programme dispatch readiness |
| Final | Combined reconciliation | P2: expanded completion must be established from actual evidence | Every other top-level unit closed |

P1 denotes silent incorrect protected output. P2 denotes recoverable failure or
material operational friction. No active publication incident requiring a P0
interrupt is claimed. Preferred order does not create artificial blocking edges
between independent functional units. Restoration may wait on the owner while
isolated code and documentation work proceeds; each unit's live acceptance must
still obtain the environment its criteria require.

## Bootstrap and closure

Publish the root ledger and outcome-based unit bodies, then their native parent
and blocked-by relationships. Keep issue #96's accepted findings and merits
declines distinguishable; the three selected documentation deliveries receive
their own tracking rather than treating #96 as one shared implementation PR.

The bootstrap PR carries this plan and the updated OpenSpec artifacts. It is a
planning delivery, not evidence that product criteria passed. No author/reviewer
is dispatched and no unit is dispatch-ready merely because it is indexed here.
The next boundary re-derives readiness after the owner reviews the plan and
selects the unit to dispatch, then prepares only that unit's context pair.

Close the programme only after the final no-PR unit has its actual author report,
independent verdict and criterion reconciliation, and the GitHub unit states and
OpenSpec task marks agree. Preserve the original completed tasks, verification
limits, unchanged exclusions and cross-programme ownership in the final record.
