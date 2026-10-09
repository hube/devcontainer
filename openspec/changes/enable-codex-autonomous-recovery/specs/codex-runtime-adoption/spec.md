Plan author - 01a11f37

# Spec Delta

## Purpose

Expose the effective execution settings required for autonomous Codex recovery
and support fresh and persistent installations without replacing user state.

## ADDED Requirements

### Requirement: Effective execution policy is verifiable
The supported integration SHALL identify the effective execution and approval
policy for desktop remote agents and delegates, and distinguish it from feature
configuration defaults. It SHALL identify incompatible managed or user settings
that prevent the supported recovery path.

#### Scenario: Feature defaults differ from session policy
- **WHEN** a remote session or delegate has an effective policy incompatible
  with automatic recovery despite compatible feature defaults
- **THEN** the integration identifies the effective incompatibility rather than
  reporting the session as compatible from the defaults alone

### Requirement: Fresh installations support the recovery contract
A fresh supported installation SHALL supply the configuration and shared-guidance
wiring required for the delivered recovery outcomes. Availability SHALL be
established through the supported desktop remote integration and a real delegate.

#### Scenario: Fresh installation exercises delegated startup
- **WHEN** an agent and delegate start authorized work in a fresh supported
  installation with an eligible setup sandbox denial
- **THEN** they consume the required guidance, use the supported automatic
  approval path, and continue in their own isolated workspaces

### Requirement: Existing installation adoption preserves user state
Adoption in an existing installation SHALL change only settings necessary for the
supported recovery contract, preserve unrelated user configuration,
authentication, and session history, and expose conflicts requiring an unresolved
policy decision rather than silently replacing user settings.

#### Scenario: Persistent state already exists
- **WHEN** necessary recovery settings are adopted into a persistent Codex
  installation containing user configuration, credentials, and session history
- **THEN** unrelated settings and persistent state remain intact and the
  resulting effective policy is verified

#### Scenario: Managed policy prevents adoption
- **WHEN** a managed policy blocks the supported recovery configuration
- **THEN** adoption reports the policy conflict and its consequence and remedy
  without overwriting that policy or claiming successful activation

### Requirement: Concurrent sessions retain separate task ownership
The delivered integration SHALL support concurrent agents using distinct branches
and worktrees while preserving other sessions' registrations, ownership records,
and shared history. Agent uncommitted contents remain re-doable under the
proposal's environment prerequisites.

#### Scenario: Concurrent task startup
- **WHEN** concurrent supported sessions establish separate task workspaces
- **THEN** each continues in its own branch and worktree without removing,
  repointing, or rewriting the other session's registered state

### Requirement: Adoption verification separates fixtures from live state
The adoption documentation SHALL provide disposable configuration-copy inputs,
synthetic protected-state baseline/readback and a separate supported live-state
capture boundary. Verification SHALL exclude credential contents from published
evidence and account for active session writes. Synthetic copy-wiring probes
SHALL NOT be presented as fresh or persistent desktop integration acceptance.

#### Scenario: Maintainer verifies configuration copying
- **WHEN** the documented copy recipe is run against fresh, persistent and
  repeated-copy disposable fixtures
- **THEN** unrelated synthetic configuration, authentication and history bytes are
  compared with their baseline, and the same comparator rejects an actually
  altered protected entry

#### Scenario: Live adoption or rollback is claimed
- **WHEN** fresh or persistent desktop adoption or rollback is reported complete
- **THEN** the supported host/client procedure and live-state readback have been
  exercised separately from synthetic fixtures, and any unavailable host/client
  verification remains explicitly unmet

```text
Harness: Codex
Harness-Version: 0.162.0
Model: GPT-6
Skills: openspec-update-change
```
