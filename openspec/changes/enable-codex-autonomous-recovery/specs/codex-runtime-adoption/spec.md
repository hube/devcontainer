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

### Requirement: Startup installs skills independently for both harnesses
Container startup SHALL invoke the maintained skills installer explicitly for
Claude and Codex and attempt both independently. A failure SHALL identify its
harness, consequence and remedy while retaining non-blocking container startup.
Fresh and repeated setup SHALL preserve unrelated user-owned state and respect
installer conflicts.

#### Scenario: Both supported harnesses can be configured
- **WHEN** the supported container starts with both harness prerequisites available
- **THEN** each receives its intended skills installation and repeated setup
  preserves unrelated user-owned configuration

#### Scenario: One harness installation fails
- **WHEN** one target's prerequisite, conflict check or installation fails
- **THEN** startup reports that target's failure and remedy, still attempts the
  other target and does not replace conflicting user-owned state to force success

### Requirement: SSH host ports are allocated automatically on localhost
The supported consumer SHALL obtain an available loopback host port for its
container SSH listener without manual per-container port selection. Concurrent
consumers SHALL remain separately reachable without taking over existing host
listeners. The integration SHALL use the runtime's native port allocation.

#### Scenario: The conventional host port is occupied
- **WHEN** a supported consumer is created while that host port is already in use
- **THEN** it obtains another available loopback mapping and the existing listener
  remains intact

#### Scenario: Two consumers are created together
- **WHEN** two supported consumers publish their SSH listeners
- **THEN** each has its own discoverable loopback mapping and can be reached
  independently

### Requirement: SSH connection identity survives mapping changes
The integration SHALL discover the actual SSH mapping of the intended consumer
and refresh its stable concrete SSH alias after creation or recreation. It SHALL
preserve unrelated SSH configuration, credentials and trust checks, and diagnose
missing, ambiguous, stale or conflicting inputs without selecting another
consumer. Actual SSH and supported desktop reconnection SHALL establish acceptance.

#### Scenario: Recreation changes the assigned host port
- **WHEN** the intended consumer is recreated with a different mapping
- **THEN** its stable alias is refreshed to the new mapping and reaches that
  consumer through SSH and the supported desktop connection

#### Scenario: Consumer discovery is unresolved
- **WHEN** the consumer identity or SSH mapping is missing, ambiguous or stale
- **THEN** connection setup reports the unresolved input and does not connect the
  alias to another consumer or retain stale settings as a successful refresh

#### Scenario: The selected alias conflicts with user configuration
- **WHEN** the managed connection entry would overwrite a user-owned alias or
  unrelated setting
- **THEN** setup reports the conflict and remedy while preserving that configuration
  and normal SSH authentication and host-key verification

### Requirement: Host onboarding identifies the activation prerequisites
Onboarding guidance SHALL identify the consuming host workspace, make startup
and shell entry target that same workspace, distinguish image consumption from
repository development, and supply preparation of the required host projects
directory. Existing directory contents SHALL be preserved and wrong-type paths
diagnosed. Owning feature procedures SHALL remain the reference for other programmes.

#### Scenario: A new consumer follows the entry guide
- **WHEN** an operator follows documented startup and shell entry
- **THEN** both target the identified consuming workspace and the required host
  projects bind source exists before container creation

#### Scenario: The projects-directory path already exists
- **WHEN** host preparation encounters an existing directory or a path of another
  type
- **THEN** directory contents remain intact and a wrong-type path produces a
  diagnosis instead of being overwritten

### Requirement: Rebuild persistence is explicit without changing its model
Guidance SHALL distinguish persistent host binds and named volumes from unmounted
sibling directories on the disposable container filesystem, using the actual
consumer mounts. It SHALL identify persistent locations for required recreation
backups and progress notes. This delivery SHALL retain the existing persistence
model and add no durability guarantee for unmounted sibling directories.

#### Scenario: An operator prepares to recreate a consumer
- **WHEN** the documented mount inspection and backup preparation are followed
- **THEN** the operator can identify which selected paths survive recreation and
  place the required backups and notes on existing persistent storage
