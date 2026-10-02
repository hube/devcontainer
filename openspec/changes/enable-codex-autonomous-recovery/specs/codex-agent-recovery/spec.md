# Spec Delta

## Purpose

Enable desktop remote Codex agents and delegates to continue authorized
work through eligible sandbox failures while respecting approval decisions
and protecting shared repository state.

## ADDED Requirements

### Requirement: Autonomous isolated task startup
An agent and its delegate SHALL establish their own branch and linked worktree
in a compatible supported remote session and continue the assigned task after
an eligible setup sandbox denial through supported automatic approval, without
routine owner intervention.

#### Scenario: Delegate recovers during setup
- **WHEN** a delegate starting authorized work encounters an eligible sandbox
  denial while creating its own branch or linked worktree
- **THEN** it obtains automatic approval through the supported runtime path,
  establishes the isolated workspace, and continues work there

#### Scenario: Setup succeeds without a denial
- **WHEN** the authorized setup operation succeeds within the effective sandbox
- **THEN** the agent continues in its own worktree without requesting escalation

### Requirement: Failure classification preserves refusal boundaries
Recovery guidance SHALL distinguish eligible sandbox denial, rejected approval,
ownership refusal, authorization failure, and ordinary command failure. Only
eligible sandbox denial SHALL enter the supported automatic escalation path.

#### Scenario: Approval is rejected
- **WHEN** automatic approval review rejects the proposed operation
- **THEN** the agent respects the rejection and considers only a materially
  safer authorized alternative, or reports the failure if none is available

#### Scenario: Worktree ownership refuses an operation
- **WHEN** setup would require another task's worktree or an ownership bypass
- **THEN** the agent stops that path and does not use escalation to bypass it

#### Scenario: Ordinary command failure
- **WHEN** a command fails for a reason unrelated to execution sandbox policy
- **THEN** the agent diagnoses that cause without treating generic permission
  wording as authorization to escalate

### Requirement: Recovery respects partial effects and protected state
An agent SHALL inspect task-owned partial effects before retrying setup. Recovery
SHALL preserve committed outputs, persistent user state, other sessions'
registrations and ownership records, and shared history. It SHALL NOT use a
primary checkout or another task's worktree as its workspace.

#### Scenario: Setup partially succeeded
- **WHEN** the failed attempt left a branch or worktree created by this task
- **THEN** the agent inspects that state and continues or retries without
  duplicating setup or changing another task's registered state

### Requirement: Authorized task inputs are obtainable
In a compatible supported session, an agent SHALL recover eligible sandbox
failures during authorized repository fetch and its required transport, then
continue the task without routine owner intervention.

#### Scenario: Fetch needs automatic escalation
- **WHEN** an authorized fetch encounters an eligible sandbox denial
- **THEN** the agent uses the supported approval path and continues with the
  obtained inputs without altering unrelated worktree registrations or history

### Requirement: Task checks can run autonomously
In a compatible supported session, an agent SHALL recover eligible sandbox
failures in representative Node subprocess tooling and task checks without
requiring routine owner intervention.

#### Scenario: Node subprocess is sandbox-denied
- **WHEN** a task check cannot launch its required subprocess because of an
  eligible execution sandbox denial
- **THEN** the agent obtains supported automatic approval, runs the check, and
  reports its actual result without representing an unexecuted check as passed

### Requirement: Reviewable output can be published autonomously
For an authorized destination and configured credentials, an agent SHALL recover
eligible sandbox failures in SSH signing and publication, then publish the
reviewable output without routine owner intervention. Authorization and signing
identity failures SHALL remain distinct from sandbox denial.

#### Scenario: Signing and publication need recovery
- **WHEN** signing or publication of authorized work encounters an eligible
  sandbox denial and the required signing identity and credentials are available
- **THEN** the agent uses the supported approval path and publishes the intended
  reviewable artifact

#### Scenario: Signing identity is unavailable
- **WHEN** the signing integration lacks the required identity
- **THEN** the agent reports the captured primary failure, its consequence, and
  the concrete remedy without claiming that automatic escalation supplies it

### Requirement: Terminal failure has an actionable handoff
When authorized recovery cannot continue, the agent SHALL preserve enough verified
context to diagnose and resume the task, including captured failure output,
protected-state implications, and the remaining dependency. Disposable partial
work SHALL remain re-doable; a per-command durable journal is not required.

#### Scenario: Delegated approval path is unavailable
- **WHEN** the supported remote runtime cannot provide delegated automatic
  approval and continuation
- **THEN** the agent identifies the owning integration or upstream dependency,
  preserves an actionable handoff, and does not substitute manual elevation or
  blanket full access as proof of autonomous completion
