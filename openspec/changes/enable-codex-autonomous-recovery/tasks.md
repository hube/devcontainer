Plan author - 01a11f37

# Tasks

Each numbered group is a functional delivery with its own activation,
documentation, and acceptance. Repository PRs within a group may land separately;
the group delivers only when the supported session consumes them together.
Groups 1–5 cover runtime deliveries; groups 6–8 deliver the selected reproducible
documentation and canonical prerequisites, and group 9 reconciles their
completion. The capability specs describe the complete change, not a claim that
its first increment delivers every requirement.

The [selected scope](proposal.md#selected-documentation-scope) and the
[disposition inventory](https://github.com/hube/devcontainer/issues/96#issuecomment-6044021452)
govern groups 6–9. Feature documentation lives in
`.devcontainer/local-features/codex/NOTES.md` and `MAINTAINERS.md`; canonical
procedures live in hube/claude-home. Each task includes its required verification;
an unavailable live check remains outstanding. Keep task progress in these marks
and evidence in the owning PRs, without converting prior receipts into new runs.

## 1. Deliver autonomous isolated task startup

- [x] 1.1 Establish delegated feasibility on the supported desktop remote
  integration using a disposable task repository: observe an eligible setup
  sandbox denial, delegated automatic approval, successful branch/worktree
  creation, and a subsequent action in that worktree without an owner prompt.
  Verify the denial and approval paths actually ran. If unavailable, capture the
  owning integration dependency and revise the minimum integration remedy before
  continuing; a manual elevation or standalone CLI result is not acceptance.
- [x] 1.2 In hube/claude-home, introduce one canonical failure-classification and
  Codex recovery procedure and reconcile the worktree and orchestration stop
  conditions that bind during setup. Verify an eligible denial reaches supported
  approval, a safe success does not escalate, and rejected approval, ownership
  refusal, and ordinary command failure retain their separate outcomes. Run the
  instruction-authoring adherence and reader-proxy review owed by those edits.
- [x] 1.3 Supply any minimum integration wiring required by 1.1 in this repository;
  reuse existing automatic review and guidance mounts where sufficient. Verify
  our configuration and inputs with focused tests that name their stubs, then
  verify effective parent/delegate policy in the supported remote session.
- [x] 1.4 Document the compatible configuration subset, how existing compatible
  sessions activate the guidance, and terminal-failure diagnosis. Verify the
  activation steps as written and obtain the required reader-proxy review.
- [x] 1.5 Demonstrate consumed guidance and runtime together: parent and delegate
  create separate task workspaces, recover eligible setup denials, inspect
  task-owned partial effects before retry, and continue work. Verify unrelated
  registrations, ownership records, and refs retain their intended state. Publish
  the verified startup outcome without claiming broader operation coverage.

## 2. Deliver autonomous retrieval of task inputs

- [x] 2.1 Extend the canonical recovery contract to authorized fetch and the
  transport required by the selected supported path. Verify sandbox denial is
  recoverable while credential, network, and genuine authorization failures are
  diagnosed as their own causes; do not duplicate the recovery procedure.
- [x] 2.2 Add any required fetch/transport wiring, focused input tests, and
  operator diagnosis to this repository. Verify only our wiring in the test
  suite, name stubs, and demonstrate the actual transport in a live remote probe.
- [x] 2.3 Starting from the delivered isolated workspace, demonstrate a parent and
  delegate obtain authorized inputs and continue without an owner prompt. Verify
  shared-state preservation and rerun the startup acceptance affected by this
  change before publishing the retrieval outcome.

## 3. Deliver autonomous execution and verification

- [x] 3.1 Extend the canonical contract and any required integration settings for
  representative Node subprocess tooling and task checks. Verify an eligible
  execution denial enters supported approval and an ordinary failed task check
  remains a failed check rather than being reported as a recovery success.
- [x] 3.2 Add focused tests for our configuration/wiring, representative live
  Node/check scenarios, and operator guidance. Verify known-broken controls fail
  and the actual supported parent/delegate commands run; do not unit-test Codex
  or OS subprocess behavior as if this repository owns it.
- [x] 3.3 Demonstrate the startup-to-inputs-to-checks flow without routine owner
  intervention, rerun earlier acceptance affected by these changes, and publish
  the new executable/checkable task outcome with its supported subset.

## 4. Deliver autonomous publication of reviewable output

- [x] 4.1 Extend recovery for SSH signing and authorized Git/GitHub publication,
  retaining the existing signing, attribution, and owner-only merge rules. Verify
  a sandbox denial, missing signing identity, unreachable agent, and rejected
  destination authorization are distinguished with captured primary failures.
- [x] 4.2 Add required wiring, focused tests, and publication/diagnosis guidance.
  Verify our signing/publication inputs with named stubs and demonstrate the real
  integration using disposable task work and an authorized test destination.
- [x] 4.3 Demonstrate the full task flow through an attributed signed commit,
  successful push, and the intended review artifact without routine owner
  intervention. Verify the commit signature and published artifact by readback,
  and rerun earlier acceptance affected by the publication changes.

## 5. Extend adoption across persistent installations

- [x] 5.1 Identify the exact effective settings and guidance wiring required by
  the delivered flows. Verify fresh and existing-install policy inspection finds
  both a compatible case and an intentionally incompatible case, including
  delegate settings rather than relying on feature defaults.
- [x] 5.2 Implement the necessary incremental adoption path with explicit handling
  of managed-policy and user-setting conflicts. Verify fixtures preserve unrelated
  configuration, authentication, and history and expose each incompatible input;
  tests cover our migration and inputs rather than third-party runtime behavior.
- [x] 5.3 Document activation, supported conflicts, rollback, and persistent-state
  preservation. Verify the documented path on fresh and persistent installations
  and obtain the required reader-proxy review.
- [x] 5.4 Demonstrate the delivered task flow on both installation paths, including
  concurrent sessions using distinct branches/worktrees. Verify effective policy,
  state preservation, and exercised approval controls; reconcile related issue
  criteria before making any issue-completion claim.

## 6. Deliver reproducible recovery documentation

- [ ] 6.1 In NOTES.md, identify the feature and desktop socket providers and
  their supported restoration routes, with a concrete escalation destination
  where the client exposes no restoration control. Verify both socket-source
  routes and retain distinct unreachable versus sandbox-restricted failures;
  verify restoration on the supported host/client integration.
- [ ] 6.2 In NOTES.md, link the official remote Codex authentication authority
  and identify its read-only completion check. Recheck the supported client and
  authentication flow, then verify remote status and desktop connection without
  publishing credentials or reauthenticating an already authenticated user.
- [ ] 6.3 In MAINTAINERS.md, provide disposable fixture preparation and define
  the protected refs, registrations and bytes at first use. Run the recipe to
  prepare the seed, ignored worktree root and protected baseline; verify distinct
  parent/delegate additions preserve that baseline.
- [ ] 6.4 Supply the baseline representation, comparator invocation, allowed
  additions and changed-baseline input. Consult the maintained control catalogue
  before choosing a helper. Show the same comparator accepting preserved state,
  rejecting an actually altered protected entry and handling permitted additions;
  retain raw results for the acceptance sections that consume it.
- [ ] 6.5 Supply startup classification case inputs and evidence for safe setup,
  ordinary failure, ownership refusal and rejected approval. Run the isolated
  safe/ordinary/ownership cases and verify their outcomes without a bypass;
  label rejection hypothetical unless independent approval records establish an
  observed rejection. Retain canonical failure classification by reference.
- [ ] 6.6 Identify the OpenSpec contributor prerequisite and setup authority,
  with an availability/version preflight. Verify missing-executable diagnosis
  and the apply-instructions command against this change. Link related-criteria
  navigation to proposal Impact and the issue actually claimed; verify those
  links and current owner dispositions without asserting the original
  non-elevated criteria of issues 74–76 were implemented.
- [ ] 6.7 Provide invocation-scoped absent/empty-agent and disposable signing
  inputs, including cleanup. Verify unreachable, reachable-empty and missing
  required identity diagnoses separately, preserving real configuration and
  credentials. Exercise genuine credential rejection only at a separately
  authorized destination; retain the actual primary failure.
- [ ] 6.8 Specify a restricted-resource input/output for the representative Node
  check and how each seat confirms its effective restriction. Run that actual
  check in parent and delegate under default and supported approved policy;
  retain denial, status, attached errors, output and matching approval decisions.
  Verify the broken check stays nonzero and the missing command stays a failure.
- [ ] 6.9 Supply a disposable configuration-copy recipe derived from the actual
  installer, with source/target and user/ownership inputs. Verify fresh,
  persistent and repeated-copy fixtures preserve unrelated synthetic TOML,
  authentication and history bytes; show their comparator rejecting an altered
  protected baseline. Name these copy-wiring probes, not desktop acceptance.
- [ ] 6.10 Provide synthetic adoption baseline/readback and a separate supported
  live-state capture method. Exclude credential contents and account for active
  history writes. Verify protected synthetic bytes with the same comparator;
  separately verify fresh/persistent host/client adoption and rollback state.
- [ ] 6.11 Run the required reader-proxy reviews of the repaired operator and
  maintainer paths and explicitly discharge each finding. Verify revised
  procedures as written and record host/client-only checks still outstanding;
  review conclusions and disposable fixtures cannot replace live acceptance.

## 7. Deliver canonical check and attribution prerequisites

- [ ] 7.1 In hube/claude-home instructions/committing.md, provide discovery of
  repository-required checks through the repository's governing configuration.
  Derive this repository's commands from its scripts and verify discovery in a
  second target with different commands. Explicitly surface checks a disposable
  fixture cannot supply instead of inventing commands or claiming unrun passes.
- [ ] 7.2 In the canonical attribution home, document the supported Codex session
  identifier producer and the unavailable-source outcome. Verify the actual
  serving session identity in desktop remote and CLI contexts, or state an
  unsupported harness branch. Reach the procedure by concise canonical reference;
  obtain a concrete owner decision before any proposed net always-on growth.
- [ ] 7.3 In the canonical attribution home, supply model display-name resolution
  from the actual exposed serving model and official authority, retaining the
  exposed-label fallback and noreply address. Verify identifier-only and
  label-only cases; avoid an exhaustive copied model table or inferred defaults.
- [ ] 7.4 Run instruction-authoring adherence with enumerated coverage and the
  required reader-proxy review in hube/claude-home, discharging each finding.
  Verify mounted canonical guidance and feature references resolve the repaired
  prerequisites together; keep procedures in their owning repository.

## 8. Bind publication observation to the intended merge

- [ ] 8.1 In MAINTAINERS.md, require the chosen merge SHA, filter the named
  workflow/main branch by that commit and verify the returned head/workflow
  identity before watching it. Verify distinct known-present merge SHAs,
  including an older merge, and diagnose absent or ambiguous matches rather than
  selecting the newest unrelated run. Include this prose in its required reader
  review and retain selection/output evidence without claiming a publication ran.

## 9. Reconcile the selected repairs

- [ ] 9.1 Reconcile every selected inventory entry on issue 96 with its landed
  repair and task-specific verification, naming any unmet host/client criterion.
  Preserve unselected accepted gaps and merits declines as recorded separate
  work. Rerun affected earlier acceptance, record exact checks and prior receipts
  separately, and verify all selected procedures and canonical prerequisites are
  consumed together before claiming the repair delivery complete.

Spec synchronization and archiving follow repair completion as separately
authorized finalization work.

```text
Harness: Codex
Harness-Version: 0.162.0
Model: GPT-6
Skills: openspec-update-change
```
