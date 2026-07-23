# Rigor levels and anti-ratchet review discipline

Status: Draft — in review on `hube/devcontainer#55`. Generalizes the
assurance-level conventions and PR circuit-breaker introduced in
[`hube/fin#5`](https://github.com/hube/fin/pull/5) into harness-neutral,
user-level agent guidance.

## Context

`hube/fin#5` encoded an **anti-ratchet kit** for agent-driven design/review
loops. It was born from `hube/fin#1`, where roughly half the review rounds
(r14–r26) accreted crash-safety machinery serving a rigor standard nobody had
chosen: with requirements unstated, each round read the draft's invariants at
their strictest defensible interpretation, demanded more mechanism, and the next
round found fault with the mechanism just added. A contest-based tripwire never
fired because no round *disagreed* with the last — each agreed and added.

fin#5 fixed this repo-locally with four moving parts:

- **Assurance levels** — required rigor stated as owner-controlled *inputs*. A
  weak level **caps** machinery (demands for more are out of scope); a strong
  level **authorizes** it. Stated as prose outcomes, with a reference ladder
  (re-doable → protected → recorded → mechanically verified → independently
  verified) and a **weak default floor** for the requirements vacuum.
- **Meets-not-exceeds review scope** — over-engineering is a valid Important
  finding, and the recommendation is *deletion*.
- **A churn circuit-breaker** — three consecutive rounds of findings confined to
  the same mechanism stop the fixing and produce an owner options memo. This
  catches uncontested accretion, which the contest-based rule cannot.
- **An altitude step** — before any state-adding fix, prefer deleting the claim
  the finding contradicts, and refuse to fix requirements that trace to no
  decided level.

fin#5 also made its guidance harness-neutral: `AGENTS.md` is canonical and
`CLAUDE.md` is a symlink to it, "for every authoring harness, not only Claude."

### What the user's global guidance already has

The **contest-based** half is already in `~/.claude/CLAUDE.md`: settled
decisions are recorded-not-defended, marked `Decided (owner, YYYY-MM-DD: url)`;
a decision contested across more than one review round escalates to the user;
and code-review scope already excludes the sufficiency of settled-decision
rationale.

### What is missing globally

The **uncontested-accretion** complement and the rigor vocabulary: the
same-mechanism circuit-breaker, meets-not-exceeds / over-engineering-is-a-defect,
the weak default floor, the altitude/delete-the-claim step, and the notion of
rigor as an owner-controlled input. "Generalize fin#5" means lifting exactly
these — the non-fin-specific parts — to cross-project, cross-harness altitude.

## Goals

1. Give every project a shared vocabulary for **owner-controlled rigor levels**
   on any dimension (not only failure/durability), with fin's durability ladder
   as the first worked instantiation.
2. Add the missing **anti-ratchet review discipline** to always-loaded user
   guidance so it binds every design/review, not only fin.
3. Make the guidance reach **every harness** the devcontainer configures (Claude
   Code, Codex, and future ones) through the existing single-file config
   channel, extended minimally.
4. Keep the always-on core lean while giving the bulk reference and the verbatim
   reviewer scope block a stable, transportable home.

## Non-goals

- **Mechanical enforcement.** Like fin#5, this is convention, not a CI check or
  a git hook. No validator is introduced.
- **Editing plugin skills.** `superpowers:brainstorming` and the review skills
  live in a read-only plugin cache; the brainstorming elicitation prompts are
  documented in the shared reference and referenced from the always-on file,
  not injected into the skill.
- **Changing how reviews are dispatched per harness** beyond documenting the
  difference. The scope *content* is neutral; the dispatch *mechanism* stays
  each harness's own.
- **Retrofitting existing project designs.** Projects adopt the vocabulary when
  next revised; until then the weak default floor governs their drafts.

## Rigor levels (the vocabulary)

Lives in the shared reference `instructions/rigor-levels.md`. Generalizes fin's
"assurance levels" so the concept applies to any dimension with an
owner-chosen rigor (durability, performance budgets, security posture,
compatibility guarantees, test rigor).

### Levels are owner inputs, not draft properties

A rigor level states how much protection a mechanism area must deliver — and, by
omission, what it need not. The asymmetry cuts both ways: a **weak level caps**
machinery (findings demanding more are out of scope) and a **strong level
authorizes** it (rigor belongs where the owner placed it). Making the strong
areas explicit is as much the point as bounding the weak ones.

### Status markers

Reusing the marker convention already in `CLAUDE.md`:

- `provisional (author-proposed)` — a standing question. The first review round
  must confirm or contest it; later rounds re-surface it as a calibration
  question until the owner ratifies or revises. Against a provisional level, a
  mechanism/level mismatch is a calibration question routed to the owner, never
  a defect with a prescribed fix.
- `Decided (owner, YYYY-MM-DD: link)` — a settled input; the review scope rule
  applies.

### Weak default floor

Absent any stated level, the default is the **weakest**: primary data must never
be damaged or lost; everything else is presumed re-doable until the owner says
otherwise. The default is weak by design — strengthening must be a deliberate
owner decision that knowingly buys machinery. The rejected alternative (default
to the strictest defensible reading of whatever invariants a draft happens to
state) is exactly what produced the fin#1 ratchet.

### Named ladders

Levels are stated as required outcomes in prose, not picks from one fixed enum.
The reference hosts **named ladders per dimension**, weakest first, and an area
may combine rungs. The first, ported verbatim from fin, is durability/failure:

1. **Re-doable** — failure is recovered by discarding partial state and
   re-running.
2. **Protected** — primary data and committed outputs are never damaged,
   whatever else is lost.
3. **Recorded** — outcomes leave durable, committed evidence a human judges.
4. **Mechanically verified** — a machine checks the property every run.
5. **Independently verified** — the check runs through a path sharing no code
   (or no author) with what it checks.

Other dimensions get a named ladder **when a real design needs one**, not
speculatively.

### Format

One row per mechanism area — `| Area | Level | Status |` — declared in a
design's own "Rigor levels" section, placed directly after Non-goals. Levels are
revised later only as a marked owner decision, never by drift.

## Anti-ratchet review discipline (the process)

The parts that bind every authoring/reviewing session. The lean, always-on
statements go **inline** in the shared `CLAUDE.md`/`AGENTS.md`; the mechanics and
counting rules go in `instructions/rigor-levels.md`.

### Altitude step before any state-adding fix

Before implementing a finding whose fix would add a state machine, protocol,
invariant, or durability mechanism, answer in order:

1. Can the finding be closed by **deleting the claim or promise it contradicts**
   instead of strengthening the mechanism? Prefer subtraction: a deleted claim
   cannot be contested next round; each added mechanism is fresh surface a later
   round can fault.
2. Does the requirement the finding protects trace to a **Decided** level or
   stated goal? If not, do not fix — route it to the owner as a requirement
   question. An author-invented invariant is not a requirement.

### Review scope: meets, not exceeds

Extends the existing "Scope of a code review" section:

- **Meets, not exceeds.** Verify the work MEETS each Decided level. A finding
  that it fails to EXCEED a Decided level is out of scope as a defect; an
  unintended-looking gap becomes a one-line calibration question to the owner —
  no severity, no prescribed fix.
- **Over-engineering is a defect.** A mechanism defending a scenario the Decided
  levels or Non-goals exclude is a valid Important finding — recommend
  **deletion**, not refinement.
- **Don't infer scope or reverse a decision.** When it is unclear whether a
  Decided level applies, or a deletion would reverse a *different* settled
  decision, ask a calibration/decision-conflict question and leave the mechanism
  in place until the owner reconciles.

### The churn tripwire: two matched halves

The existing global rule is the contest-based half. This design adds its
complement and presents them as a pair:

- **Contested twice** (disagreement-churn) — a decision contested across more
  than one round → stop and ask the owner. *(existing)*
- **Three rounds confined to the same section or mechanism** (agreement-churn —
  each round agrees with the last and *adds*) → stop fixing that mechanism and
  record an owner options memo: *finish the machinery / simplify to a weaker
  stated level / accept the risk explicitly*. **(new)**

The thresholds differ deliberately: disagreement is a sharper signal than
agreement, so a contested decision escalates after two rounds while accretion is
allowed three before the breaker fires.

**Guard against false positives.** The breaker fires on *repetition on the same
ground*, not on breadth. Deliberate multi-angle review that sweeps many
mechanisms once is not churn; three rounds circling the *same* mechanism is.
(This preserves the owner's standing note on fin#1 that broad early review is
wanted, and escalation is only for repetition or decision-contradiction.)

Counting mechanics (in the reference): a **round** is one aggregated review cycle
against a single named head — concurrent reviewers at one head are one round, a
re-review after new commits is the next. Recurrence is counted **per mechanism**;
the author/orchestrator owns the count, and a reviewer only *discloses*
recurrence. The breaker blocks only the churning mechanism — reviews and fixes
elsewhere continue, and further findings against a blocked mechanism are
collected into its memo rather than answered. Resume only after the owner picks.

### Defer implementation-level correctness

Anything whose truth is established by **running code** — I/O ordering,
concurrency windows, exact library or platform semantics — is resolved against
real code with a required fixture, not in prose. "Defer to implementation with a
required fixture" is a legitimate disposition for such a finding, unless the
stated guarantee is itself unmeetable.

### Ratification triggers

A provisional or unstated level must be put to the owner when either occurs: the
design gains its first mechanism that exists **only** to serve that level; or the
churn breaker fires.

### Owner checkpoint cadence (autonomous loops only)

Scoped explicitly to autonomous/unattended review loops (like fin#1): post a
compressed delta-and-open-questions summary to the owner every **10 rounds**, or
immediately whenever **all** review activity is blocked (e.g. every open finding
sits behind a churn breaker). Do not rely on the owner noticing a spiral;
schedule the checkpoint. In attended work this rule is inert.

### Brainstorming: elicit levels first

When brainstorming any feature involving failure handling, durability, or
auditability, elicit rigor levels **before designing mechanisms** — these are
questions about the owner's tolerance, answerable on day one:

- If this fails midway, is re-doing the whole operation acceptable recovery?
- What must never be lost or damaged, even in a crash? (Usually a short list;
  everything off it is presumed re-doable.)
- Who consumes the audit trail — a human, a program, a future auditor? Must its
  conclusions be *recomputable* or *judged from evidence*?
- How often does this run, and is a human present when it does?

Record answers as `provisional (author-proposed)` levels in the draft.

### Thresholds

The breaker's **3 consecutive same-mechanism rounds** and the checkpoint's **10
rounds** are stated as concrete defaults — the values fin uses, carried forward
by owner decision — with an explicit "tune per project" note. They are a chosen
starting point, not an empirically measured optimum. `CLAUDE.md` states the
rules; the numbers live in the reference.

## Placement across harnesses

### The constraint: a single-file cross-harness channel

The devcontainer shares agent guidance across harnesses through **one host file,
bind-mounted under each harness's own instruction filename** — the same bytes
dual-named:

```
host  ~/.claude/CLAUDE.md  →  Claude Code:  ~/.claude/CLAUDE.md  (+ .claude-1/2/3)
host  ~/.claude/CLAUDE.md  →  Codex:        ~/.codex/AGENTS.md
```

Everything else in a harness's config dir is a **container-local named volume**;
only `CLAUDE.md` (and `projects/`) is bind-mounted from the host. Two
consequences:

1. **Host supporting files do not transport.** A host `~/.claude/docs/foo.md`
   with no mount is invisible inside every container.
2. **`@import` diverges.** Claude Code expands `@path` imports in `CLAUDE.md`;
   Codex reads `AGENTS.md` **wholesale** and does not. An `@import` pointer would
   silently no-op in Codex. (Established in the git-commit-attribution design:
   Codex's `agents_md` loader reads `AGENTS.md` wholesale with no `@path`
   expansion — a patch-stable property of the loader, not a version-specific
   one.)

So fin's three-file split cannot simply be replicated on the host `~/.claude`
tree — fin transports because a project repo is checked out whole in the
container; the global config is not.

### Hybrid: inline discipline + directory-mounted reference

- The **lean always-on discipline** (rigor levels exist + pointer, altitude
  step, meets-not-exceeds, the matched-pair tripwire, defer-to-fixture) goes
  **inline** in the shared `CLAUDE.md`/`AGENTS.md`, guaranteed to load in every
  harness.
- The **bulk reference** (`rigor-levels.md`) and the **verbatim reviewer scope
  block** (`review-dispatch-scope.md`) go in a shared `instructions/` directory,
  referenced by **plain textual pointer, never `@import`**, so both harnesses
  read the pointer identically and open the file the same way.

### The mount

A **read-only** bind mount exposes the shared directory at one **harness-neutral
container path** so a single pointer resolves everywhere:

```
host  ~/.claude/instructions/  →  ~/.agents/instructions   (bind, readonly)
```

`~/.agents/instructions` sits under neither `.claude` nor `.codex`, so the same
pointer string in the shared file resolves in every harness's container. The
same container user runs every harness, so `~` is identical across them.

**Ownership: consumer-declared, once.** Per the repo's mount-ownership convention
(`docs/feature-authoring.md`), a source path specific to one harness or host
layout is **consumer-declared**, so hardcoding it does not leak that layout into
otherwise-neutral Feature source. `~/.claude/instructions` is Claude-layout-
specific, so the mount is declared **once** in the project `devcontainer.json`,
not by each Feature. Declaring it per Feature would both leak the `.claude`
layout into the neutral Codex Feature and give the single `~/.agents/instructions`
target duplicate owners. Each harness Feature owns only the stable container
*target* — it references the path in its guidance pointer and **warns at
postStart when the mount is absent** (problem/consequence/remedy, non-blocking).
This mirrors the `git-commit-attribution` consumer-declared spec mount already
cited below.

**Read-only.** The instructions are read, never written, so the mount is
`readonly`: an approved/full-access command in any harness must not be able to
alter the shared host guidance that every container and session reads. (The
`ssh` Feature's `known_hosts` `bind,readonly` is the in-repo precedent.)
Implementation verifies both that a container write is refused and that a host
edit remains visible.

### Harness-neutral content

The shared file's bytes are read by every harness, so its content must be
harness-neutral: no `@import` as load-bearing, no single-harness tool as the only
path. Where dispatch mechanics genuinely differ, use per-harness subsections —
mirroring the existing `## Claude Code` / `## Codex` split already in
`CLAUDE.md` (e.g. reviewer dispatch: Claude via the Agent tool; Codex via
collaboration jobs). The reviewer **scope block itself** is neutral text and
transports unchanged.

### Extensibility to new harnesses

To add harness *N*:

1. its devcontainer Feature mounts the shared canonical file under *N*'s
   instruction filename (e.g. `GEMINI.md`) — the existing per-Feature pattern,
   each harness's file mount having its own distinct target; and
2. **no new instructions mount is needed** — the single consumer-declared
   `~/.agents/instructions` mount already serves every harness in the container.
   *N*'s Feature owns only the target-path reference and the postStart
   absent-mount warning.

Content stays neutral; add a per-harness subsection only where dispatch
mechanics differ.

## Architecture by repo

### `hube/claude-home` (content)

- **`CLAUDE.md`** — fold the lean always-on discipline into existing sections:
  design-doc guidance gains rigor-levels-are-inputs + the altitude step +
  defer-to-fixture; "Scope of a code review" gains meets-not-exceeds,
  over-engineering-is-a-defect, and don't-infer-or-reverse; the escalation rule
  gains the same-mechanism breaker as the matched complement to the existing
  contested-twice rule; and a plain-text pointer to `~/.agents/instructions`.
- **`instructions/rigor-levels.md`** (new) — the full vocabulary reference,
  breaker counting mechanics, ratification triggers, checkpoint cadence,
  thresholds, and brainstorming elicitation prompts.
- **`instructions/review-dispatch-scope.md`** (new) — the canonical reviewer
  scope block, included verbatim in every review dispatch.
- **`.gitignore`** — the repo excludes everything by default (`*`) with an
  allow-list. New `!instructions` and `!instructions/**/*` includes are
  **required**, or the new files are silently untracked.

### `hube/devcontainer` (plumbing)

- **Consumer `devcontainer.json`** — declares the mount **once**, read-only:
  `source: ${localEnv:HOME}/.claude/instructions` →
  `target: /home/${localEnv:USERNAME:devcontainer}/.agents/instructions`, `readonly`.
  One consumer-declared mount serves every harness in the container — no
  per-Feature and no per-`.claude-N`-account duplication.
- **`local-features/claude`** and **`local-features/codex`** — own only the
  stable container target `~/.agents/instructions`: each references it in the
  shared guidance pointer and **warns at postStart when the mount is absent**
  (problem/consequence/remedy, exit 0 — the repo's non-blocking convention), so a
  container missing the consumer mount stays usable.
- Feature `NOTES.md` documents the consumer mount users must add, per the repo's
  docs conventions.

## Rejected alternatives

### Keep "assurance levels" concrete (durability-only)

Rejected. Porting fin's ladder verbatim as the canonical global vocabulary
frames everything around failure/durability/audit; other dimensions (perf,
security, compatibility) bolt on awkwardly. Generalizing to "rigor levels" with
named per-dimension ladders keeps fin's ladder intact as one instantiation while
covering the rest.

### Encode the reviewer scope block as a skill

Rejected. The block's defining use is **verbatim transclusion into a
*subagent's* prompt**; the consuming reviewer inherits nothing and (per the
superpowers `SUBAGENT-STOP` rule) ignores skill bootstrapping, so the block must
exist as retrievable literal text regardless. A skill wrapper adds a layer
without adding capability and muddies the verbatim boundary with frontmatter and
meta-instructions. A file whose entire content is the block transcludes cleanly.
Discoverability is served instead by the always-on `CLAUDE.md` pointing at the
file as the canonical source.

### Mirror fin's split on the host tree with no plumbing change

Rejected. The single-file cross-harness channel means host supporting files
never reach containers, and `@import` diverges between Claude Code and Codex. The
split only transports if a directory mount is added — which this design does.

### Inline everything into the one shared file (no plumbing change)

Rejected as the whole answer, though its always-on half is adopted. Inlining the
bulk reference and the verbatim block would bloat the always-loaded file and
lose the clean copy-from-a-file model for the reviewer block. The hybrid keeps
the always-on discipline inline and moves only the bulk/verbatim material to the
mounted directory.

### No fixed thresholds

Rejected. Qualitative-only guidance ("a few rounds", "periodically") is not
actionable out of the box. fin's 3-round breaker and 10-round checkpoint ship as
concrete defaults with a "tune per project" note.

### Exclude the owner-checkpoint cadence from global guidance

Rejected. It is loop-operations detail, but the owner runs autonomous review
loops, so it earns its place — gated explicitly to autonomous/unattended loops
so it never misfires on attended work.

### Put the design doc in `hube/claude-home`

Rejected. claude-home's `*`-exclude gitignore fights doc files, and the
established precedent is that cross-harness agent-config designs
(git-commit-attribution, agent-skills-bootstrap) live in
`hube/devcontainer/docs/designs`, whose PR review naturally covers the plumbing
change.

## Open questions

- **Host/container path parity — resolved (author-proposed, pending owner
  ratification).** An agent run **directly on the host** (outside any
  devcontainer) has the files at `~/.claude/instructions/` and would not resolve
  the container-only `~/.agents/instructions`. Resolution: the claude-home
  install/deploy step creates a host symlink
  `~/.agents/instructions → ~/.claude/instructions`, so the single pointer
  resolves in every environment, host or container. The alternative — declaring
  direct-host sessions out of scope and keeping the mount devcontainer-only — is
  available if the owner prefers a smaller surface; it is not the default because
  it would strand direct-host Codex/Claude sessions that the shared pointer
  otherwise reaches.
- **Confirm deployed `CLAUDE.md` parity at implementation time.** The deployed
  `~/.claude/CLAUDE.md` must match claude-home's tracked copy before the new
  inline discipline and pointer ship. They are byte-identical in the current
  environment; because the deployed file is a mount of the host checkout, the
  implementation should re-confirm parity rather than assume it. Also confirm the
  `instructions/` mount lands in every harness container.

## Related

- `hube/fin#5` — the repo-local original this generalizes.
- `hube/fin#1` — the review loop whose ratchet motivated fin#5.
- `hube/devcontainer/docs/designs/2026-07-10-git-commit-attribution-design.md` —
  precedent for the shared-file `CLAUDE.md`→`AGENTS.md` mount and cross-repo
  agent-config designs.
- The `fin-pr1-review-loop` project memory — the owner's standing note that
  broad multi-angle review is deliberate and escalation is for repetition or
  decision-contradiction.

## Changelog

- 2026-07-22: Initial draft.
- 2026-07-22: Review round 1 (devcontainer#55). Instructions dir mounts **once**
  per harness feature (account-neutral target), not per `.claude-N` account;
  softened the deployed-`CLAUDE.md` open question to a parity check (byte-identical
  in the current environment); cited `codex-cli 0.144.5` as the provenance for the
  `@import`-divergence claim; noted the tripwire threshold asymmetry is deliberate.
- 2026-07-23: Review round 2 (devcontainer#55). Dropped the pinned `codex-cli`
  patch version from the `@import`-divergence citation (installed version is
  `0.144.4`, not the inherited `0.144.5`, and the wholesale-read behavior is
  patch-stable, so the citation now names the loader behavior and prior design
  without a rotting version pin).
- 2026-07-23: Review round 4 (devcontainer#55, Codex reviewer). Instructions
  mount is now **consumer-declared once** (Claude-layout-specific source, per
  `feature-authoring.md`) and **read-only**, replacing the per-Feature mount that
  duplicated ownership; Features own only the container target and warn at
  postStart when it is absent. Resolved the host/container parity open question
  to an author-proposed host symlink (pending owner ratification). Removed the
  unsubstantiated "proven on fin" wording from the thresholds (owner-chosen
  defaults, not a measured optimum).
