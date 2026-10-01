# Proposal

Author - 01a0f4e9

## Why

Codex agents performing ordinary development work in this devcontainer encounter
sandbox denials that interrupt Git setup, SSH operations, and Node tooling;
blanket permission-failure stop conditions prevent supported automatic recovery.
Enable desktop remote agents and their delegates to complete routine authorized
work with minimal human intervention while protecting human work, committed
outputs, and other sessions' worktree ownership.

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

Private Git administration, a custom command broker, blanket full access,
additional Codex client support, and eliminating all upstream sandbox defects
are outside the initial scope. Validator liveness and alias lifecycle remain
independent work unless they block the supported workflow.

## Rigor Levels

These levels cap the machinery needed for this delivery. Settled scope choices
are owner inputs; proposed tolerances require ratification before a mechanism
exists solely to serve them. Existing data-integrity and ownership protections
remain binding regardless of provisional levels.

| Area | Required outcome and limit | Status |
| --- | --- | --- |
| Routine execution | Authorized desktop remote agents and delegates can use supported automatic approval and recovery without routine owner prompts. Non-elevated execution and private Git administration are not required outcomes. | Decided (owner, 2026-10-01, in session) |
| Primary-work integrity | Protect human-authored work, committed outputs, other sessions' worktree registrations and ownership, and shared history against unauthorized changes. Approval is not permission to use another session's workspace or bypass ownership refusals. Adversarial containment of an approved command is not an added guarantee. | Governing protection floor; citing the shared instruction corpus |
| Failure recovery | Re-doable: the agent's disposable partial work may be discarded and rerun without damaging protected state. Inspect side effects before retrying; recovery is bounded and respects rejected approvals. Crash-proof preservation of all in-progress work is not required. | provisional (author-proposed) |
| Evidence and handoff | Record enough verified context to diagnose a terminal failure and resume the task. Per-command durable journals and independently reconstructable audit trails are not required. | provisional (author-proposed) |
| Acceptance verification | Mechanically check representative delegated operations, concurrent work, and configuration adoption when delivering or changing the supported integration. Checks demonstrate their target was exercised. Independent verification on every task and a new standing process-enforcement service are not required. | provisional (author-proposed) |
| Compatibility and adoption | Cover fresh and existing devcontainers for desktop remote sessions and delegates, preserving persistent user state. Standalone CLI is a diagnostic baseline; other clients and universal upstream-defect elimination are outside this delivery. | Decided (owner, 2026-10-01, in session) |

The [shared rigor discipline](https://github.com/hube/claude-home/blob/main/instructions/rigor-levels.md)
governs calibration. Stronger protection, audit, or verification machinery needs
an explicit owner requirement rather than accumulation through review findings.

## Capabilities

### New Capabilities

- `codex-agent-recovery`: Desktop remote agents and delegates complete routine
  authorized operations through supported automatic approval and safe recovery,
  preserve protected work, and escalate actionable failures when recovery is
  unavailable or authorization is unresolved.
- `codex-runtime-adoption`: Fresh and existing devcontainer installations expose
  verifiable effective Codex execution settings and an adoption path that
  preserves user configuration and persistent state.

### Modified Capabilities

None.

## Impact

The Codex local feature's configuration, installation/adoption path, acceptance
coverage, and eventual operator guidance are affected. Canonical instruction
changes belong to hube/claude-home and require coordinated delivery there;
this proposal changes no instructions or runtime behavior itself. No new
service or runtime dependency is proposed.

[Git-state issue #74](https://github.com/hube/devcontainer/issues/74) requires
explicit reconciliation of its normal-sandbox and elevation-removal criteria
with the owner-selected execution scope; the issue is not closed by this
proposal. The supported workflow must address the consumer impact of
[Node subprocess issue #75](https://github.com/hube/devcontainer/issues/75) and
[SSH issue #76](https://github.com/hube/devcontainer/issues/76), while their
non-elevated compatibility defects remain separately assessable.
[Validator issue #67](https://github.com/hube/devcontainer/issues/67) and
[alias issue #77](https://github.com/hube/devcontainer/issues/77) retain
independent closure criteria.

```text
Harness: Codex
Harness-Version: 0.159.3
Model: GPT-6
Skills: superpowers:using-superpowers, superpowers:systematic-debugging, openai-docs, superpowers:brainstorming, openspec-explore, superpowers:receiving-code-review
```
