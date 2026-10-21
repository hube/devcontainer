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

### Requirement: Recovery prerequisites and acceptance are reproducible
The recovery documentation SHALL identify supported socket-restoration routes
and remote authentication prerequisites, and supply the disposable fixture,
protected baseline, comparison and diagnostic inputs needed to reproduce startup,
retrieval, checks and publication acceptance. Canonical recovery, repository-check
discovery and attribution producers SHALL retain their owning corpus home.

#### Scenario: Maintainer reproduces preservation acceptance
- **WHEN** a maintainer follows the documented disposable recovery recipe
- **THEN** the fixture and comparison inputs are obtainable, intentional task
  additions are distinguished, and the same comparator rejects an altered
  protected baseline while accepting preserved state

#### Scenario: Representative check exercises recovery
- **WHEN** a parent and delegate verify the documented Node recovery case
- **THEN** the actual check encounters a restriction established from each
  actor's effective policy, its denied invocation and approved retry are retained,
  and ordinary broken or missing-command cases remain failed checks

#### Scenario: Prerequisite requires host or canonical input
- **WHEN** the recovery path requires restored forwarding, remote authentication,
  repository checks or publication attribution
- **THEN** documentation identifies the supported provider or canonical producer
  and its completion check, or the concrete unavailable-input diagnosis, without
  copying canonical procedures into the feature guide

#### Scenario: Publication outcome is selected
- **WHEN** a maintainer observes publication for a selected merge
- **THEN** the selected run matches that merge SHA, named workflow and main branch,
  and absent or ambiguous matches are diagnosed rather than replaced by the latest
  unrelated run

### Requirement: Attribution validation terminates with an actionable outcome
Attribution validation SHALL return within a documented finite bound when its
trailer parser stalls. Timeout SHALL be unsuccessful validation in every
enforcement mode, reject a hook-invoked commit, and identify the problem,
consequence and supported recovery separately from unavailable tooling and an
ordinary parser failure.

#### Scenario: Trailer parsing stalls
- **WHEN** the trailer parser does not complete within its finite bound
- **THEN** validation terminates unsuccessfully with a distinct timeout diagnosis
  rather than waiting indefinitely or reporting the message as checked

#### Scenario: A commit hook encounters the timeout
- **WHEN** hook-invoked validation times out
- **THEN** the commit is rejected and the diagnosis preserves the attribution
  requirement while identifying the supported recovery path

#### Scenario: A valid message parses normally
- **WHEN** a valid attributed message is parsed within the bound
- **THEN** the existing attribution checks complete with their actual result

### Requirement: JSON publication preserves Unicode content
The effective image tooling for the supported JSON publication path SHALL
preserve Unicode text exactly, including multibyte characters at input-buffer
boundaries and large bodies supplied through standard input or files. A command's
successful status SHALL NOT substitute for exact content verification when
establishing this delivery's acceptance.

#### Scenario: A multibyte publication body crosses an input boundary
- **WHEN** the effective image tooling serializes such a body from standard input
  or a file
- **THEN** decoding the JSON yields the complete original text without replacement,
  loss or alteration

#### Scenario: Publication integrity is verified
- **WHEN** the selected path publishes an authorized Unicode body
- **THEN** authoritative body readback agrees exactly with the intended content
  before publication success is claimed

#### Scenario: A maintainer retires the jq compatibility overlay
- **WHEN** the dedicated local jq Feature is considered for removal
- **THEN** package-provided jq without the overlay meets the same Unicode and
  exact-publication acceptance on every supported published image/architecture
  before the overlay and consumer declaration are removed

### Requirement: GitHub authentication prerequisites are reproducible
The GitHub CLI feature guidance SHALL supply the host-token and remoteEnv wiring,
existing token precedence and remote authentication completion check. It SHALL
distinguish GitHub CLI account state from SSH Git transport and identify missing
inputs without exposing credentials or replacing unrelated stored accounts.

#### Scenario: A consumer configures runtime authentication
- **WHEN** an operator follows the documented token-wiring path
- **THEN** the required host and consumer inputs are obtainable, precedence is
  explicit and remote authentication can be checked without printing a token

#### Scenario: Authentication input is unavailable
- **WHEN** the required runtime token is unset or empty
- **THEN** the documented diagnosis identifies the consequence and remedy while
  preserving unrelated stored accounts

### Requirement: Credential recovery identifies the intended volume
Credential-recovery guidance SHALL provide read-only identification of the GitHub
CLI volume mounted by the intended consumer before its existing removal
procedure. Missing or ambiguous targets SHALL be diagnosed without guessing.
The existing account-logout alternative SHALL remain available; verification
SHALL NOT require deletion of real credentials.

#### Scenario: Another consumer has a similar credential volume
- **WHEN** an operator identifies the selected consumer's mounted volume
- **THEN** the result selects that exact volume and excludes the other consumer's
  volume before any removal operation

#### Scenario: A credential-volume target cannot be established
- **WHEN** the selected consumer or matching mount is missing or ambiguous
- **THEN** the procedure reports that unresolved target and does not supply a
  guessed deletion target

### Requirement: Runtime acceptance results are interpretable
Maintainer guidance SHALL define the runtime matrix's control, treatment,
omission, restoration and final result labels, their expected outcomes and the
evidence of system Bubblewrap selection. Operator guidance SHALL link to that
authority. These definitions SHALL agree with the maintained script without
changing runtime settings, supported backends or acceptance guarantees.

#### Scenario: A maintainer interprets a runtime result
- **WHEN** a maintainer follows an emitted case label to its documented meaning
- **THEN** the case, expected result and system-Bubblewrap selection evidence are
  identifiable and agree with the maintained runtime script
