# Rigor levels and anti-ratchet review discipline

Status: Accepted (`hube/devcontainer#55`). Content implemented in
`hube/claude-home#9`; plumbing in review on `hube/devcontainer#59`.
Generalizes the assurance-level conventions and PR circuit-breaker introduced
in [`hube/fin#5`](https://github.com/hube/fin/pull/5), as since revised through
[`hube/fin#48`](https://github.com/hube/fin/issues/48), into harness-neutral,
user-level agent guidance.

## Context

`hube/fin#5` encoded an **anti-ratchet kit** for agent-driven design/review
loops. It was born from `hube/fin#1`, where review rounds r14–r26 accreted
crash-safety machinery serving a rigor standard nobody had chosen: with
requirements unstated, each round read the draft's invariants at their
strictest defensible interpretation, demanded more mechanism, and the next
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

### fin's conventions have evolved since fin#5

The fin guidance did not stop at fin#5. Its current files (`AGENTS.md`,
`docs/designs/CONVENTIONS.md`, `docs/prompts/design-review-dispatch.md`,
`docs/prompts/reader-proxy-review-dispatch.md`) — revised through the fin#47
review and the fin#48 guardrails (landed in fin PR #54) — add, generalizably:

- **A breaker boundary** — the circuit-breaker routes *unresolved requirement
  questions* to the owner; it is not a mechanism for declining an instruction
  the owner has already given.
- **Review-exchange proportionality** — rules for both sides of a review
  exchange: reply in the register the finding deserves, concede separately
  from contesting, and ask what a reply changes before writing it.
- **Proportioned findings** — a defect whose whole remedy is a correction in
  place is reported as one line, and a remediated error is closed.
- **Change-sequencing guardrails** (fin#48) — design-first PR separation,
  operator docs written before the implementation they describe, and a
  reader-proxy review on PRs that author operator-facing prose.
- **The reader-proxy dispatch** — a context-deprived reviewer prompt whose
  deprivation is the instrument.

This design lifts the **current** state of that guidance, not the fin#5
snapshot; each piece lands in the sections below. (fin#48 also retired fin's
in-repo implementation plans; the matching claude-home plan-location rules are
tracked separately in that repository — recorded in fin#48 itself — and are
out of scope here.)

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
rigor as an owner-controlled input — plus every post-fin#5 addition listed
above (none is in the global guidance). "Generalize fin" means lifting exactly
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
4. Keep the always-on core lean while giving the bulk reference and the
   verbatim dispatch blocks a stable, transportable home.

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
- **Direct-host agent sessions.** Agents run directly on the host, outside the
  devcontainer, are out of scope; the mechanism is devcontainer-only. Decided
  (owner, 2026-07-23:
  https://github.com/hube/devcontainer/pull/55#issuecomment-5060789892). No host
  symlink and no host-side `AGENTS.md` wiring is added — the
  `~/.agents/instructions` mount and the shared-file mounts exist only inside
  containers.

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
  question until the owner ratifies or revises — ratification may take longer
  than one round, and the level stays provisional until it happens. Against a
  provisional level, a mechanism/level mismatch is a calibration question
  routed to the owner, never a defect with a prescribed fix.
- `Decided (owner, YYYY-MM-DD: link)` — a settled input; the review scope rule
  applies. Where the decision was made in conversation and no artifact exists,
  `Decided (owner, YYYY-MM-DD, in session)` rather than no marker at all.

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
design's own "Rigor levels" section, grouped with wherever the design states
its goals and scope exclusions, so levels read as owner inputs rather than
properties discovered later in the draft. The placement rule is proximity to
the scope statements, whatever the document's structure calls them; in
documents following the Goals/Non-goals convention that means directly after
Non-goals. Levels are revised later only as a marked owner decision, never by
drift.

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
  no severity, no prescribed fix, because a prescription presupposes the answer
  (that the level should rise) and a severity label puts the question into the
  findings queue, creating closure pressure to add mechanism before the owner
  has decided.
- **Over-engineering is a defect.** A mechanism defending a scenario the Decided
  levels or Non-goals exclude is a valid Important finding — recommend
  **deletion**, not refinement, with equal credit for finding removable
  machinery as for finding missing machinery.
- **Don't infer scope or reverse a decision.** When it is unclear whether a
  Decided level applies, or a deletion would reverse a *different* settled
  decision, ask a calibration/decision-conflict question and leave the mechanism
  in place until the owner reconciles.

### The churn tripwire: two matched halves

The existing global rule is the contest-based half. This design adds its
complement and presents them as a pair:

- **Contested twice** (disagreement-churn) — a decision contested across more
  than one round → stop and ask the owner. *(existing)*
- **Three rounds confined to the same section or mechanism** (motivated by
  agreement-churn — uncontested accretion, where each round agrees with the
  last and *adds*) → stop fixing that mechanism and record an owner options
  memo naming the remedy that fits the cause; see **Remedy scoped to cause**
  below. **(new)**

The thresholds differ deliberately: disagreement is a sharper signal than
agreement, so a contested decision escalates after two rounds while repetition
is allowed three before the breaker fires.

**Guard against false positives.** The breaker fires on *repetition on the same
ground*, not on breadth. Deliberate multi-angle review that sweeps many
mechanisms once is not churn; three rounds circling the *same* mechanism is.
(This preserves the owner's standing note on fin#1 that broad early review is
wanted, and escalation is only for repetition or decision-contradiction.)

Counting mechanics (in the reference): a **round** is one aggregated review cycle
against a single named head — concurrent reviewers at one head are one round, a
re-review after new commits is the next. Recurrence is counted **per mechanism**;
the author owns the count, and a reviewer only *discloses* recurrence. The
breaker blocks only the churning mechanism — reviews and fixes elsewhere
continue, and further findings against a blocked mechanism are collected into an
options memo rather than answered. Resume only after the owner picks.

**The breaker routes unresolved requirement questions to the owner; it is not a
mechanism for declining an instruction the owner has already given.** A round
whose finding arrives with the owner's decision attached is fixed, not
escalated, even when it is the third consecutive round confined to that
mechanism.

**Remedy scoped to cause.** The breaker's trigger stays recurrence alone —
three consecutive rounds confined to the same section or mechanism, with no
narrower accretion-only reading. Its owner options memo names the remedy that
fits *why* the rounds recurred (false claims, distinct genuine defects, an
unfixed recurring defect, reviewer disagreement, adjacent breakage, or
tolerable risk); the full table is in the reference. Recurrence on a
**mechanism** stops fixing it and waits for the owner; recurrence on a
**claim** is self-authorising — delete and disclose rather than stopping,
since subtraction cannot over-build. Decided (owner, 2026-08-05:
https://github.com/hube/claude-home/pull/9#issuecomment-5195559451).

### Defer implementation-level correctness

Anything whose truth is established by **running code** — I/O ordering,
concurrency windows, exact library or platform semantics — is resolved against
real code with a required fixture, not in prose. A design specifies **what it
guarantees**; it specifies mechanism only where the guarantee itself demands
one. "Defer to implementation with a required fixture" is a legitimate
disposition for such a finding, unless the stated guarantee is itself
unmeetable.

### Review exchanges: proportionality

Binds both sides of a review exchange; ported from fin's current `AGENTS.md`:

- **Reply in the register the finding deserves, not the one it arrived in.** An
  inflated minor finding is answered briefly and corrected; matching its
  apparatus doubles the cost of an error already agreed on.
- **Concede separately from contesting.** A concession sharing a message with a
  rebuttal reads as a preamble to the rebuttal and invites another round; post
  the concession by itself.
- **Ask what a reply changes before writing it.** A reply is commentary,
  however correct, unless it changes a named artifact or is itself the one-line
  proposal of a guard. This governs how much a reply elaborates, not whether it
  is given — every finding still receives an explicit accept or decline.

The reviewer-side complements travel inside the verbatim scope block rather
than as separate inline rules: a defect whose whole remedy is a correction in
place is one line naming the correction, every artifact that must change, and
its own disposition — never its own section; and a remediated error is closed —
a guard, if worth building, is proposed in one line as a change to a named
artifact, and a cause is stated at most once.

### Change sequencing

The fin#48 guardrails, generalized:

- **A design change and a change to the artifact it governs land in separate
  PRs, design first.** Conformance to a specification written in the same PR is
  not evidence — the author chose both sides. This binds author-originated
  changes; when the owner directs a specification change, the direction and its
  first application may share a PR. A design PR may carry the mechanical
  relocation its own decision entails, but may not author new prose in the
  governed artifact.
- **Operator-facing guidance is written before the implementation it
  describes**, as a check that the requirements are satisfiable. Documentation
  written against a finished tool cannot report that the tool is missing a
  command; it can only describe the workaround. A satisfiability check is not
  conformance evidence, so it does not trigger the separation rule above.
- **A reader-proxy review is dispatched on any PR that authors or revises
  operator-facing prose.** A PR that only repairs a reference — a renamed path,
  a deleted link — does not trigger it; there is no new prose for a new reader
  to fail on, and firing the review there teaches everyone to treat the rule as
  noise. Its findings are advisory while effectiveness data is collected: they
  are weighed but do not block, and the dispatch obligation is discharged by
  running the review and dispositioning its output. Decided (owner, 2026-08-05:
  https://github.com/hube/claude-home/pull/9#issuecomment-5194813422).

### The reader-proxy dispatch

A reader-proxy is a reviewer given the operator documentation under review and
nothing else — no design, no source, no issue or PR history — reporting only:
terms used before they are defined; steps it cannot complete from the text
alone; artifacts named without their producer; and instructions whose success
condition is not stated. The deprivation is the instrument: a reader-proxy
handed the design becomes an ordinary reviewer, and those four categories are
exactly what a design-holding reviewer is structurally unable to see — so the
orchestrator must not supply further context even on request.

Like the reviewer scope block, the dispatch is verbatim text and gets the same
treatment: its own file in the shared `instructions/` directory. The reviewer
scope block is **not** included in a reader-proxy dispatch, which carries no
context beyond its own prompt and the documentation under review.

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

When brainstorming any feature that touches a dimension with owner-chosen
rigor, elicit that dimension's levels **before designing mechanisms**. Whatever
the dimension, the questions are about the owner's tolerance, not the design —
what outcome must hold, what may be lost or degraded, who consumes the
evidence, how often the scenario arises — so they are answerable on day one.
Record answers as `provisional (author-proposed)` levels in the draft.

The durability/failure dimension's questions, ported from fin, are the worked
example:

- If this fails midway, is re-doing the whole operation acceptable recovery?
- What must never be lost or damaged, even in a crash? (Usually a short list;
  everything off it is presumed re-doable.)
- Who consumes the audit trail — a human, a program, a future auditor? Must its
  conclusions be *recomputable* or *judged from evidence*?
- How often does this run, and is a human present when it does?

Other dimensions derive their elicitation questions the same way — from the
owner's tolerance, not from the draft's invariants.

### Thresholds

The breaker's **3 consecutive same-mechanism rounds** and the checkpoint's **10
rounds** are stated as concrete defaults — the values fin uses, carried forward
by owner decision. They are a chosen starting point, not an empirically
measured optimum. `CLAUDE.md` states the rules; the numbers live in the
reference.

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
   expansion.)

So fin's three-file split cannot simply be replicated on the host `~/.claude`
tree — fin transports because a project repo is checked out whole in the
container; the global config is not.

### Hybrid: inline discipline + directory-mounted reference

- The **lean always-on discipline** (rigor levels exist + pointer, altitude
  step, meets-not-exceeds, the matched-pair tripwire, defer-to-fixture,
  exchange proportionality, the change-sequencing guardrails) goes **inline**
  in the shared `CLAUDE.md`/`AGENTS.md`, guaranteed to load in every harness.
- The **bulk reference** (`rigor-levels.md`) and the **verbatim dispatch
  blocks** (`review-dispatch-scope.md`, `reader-proxy-review-dispatch.md`) go
  in a shared `instructions/` directory, referenced by **plain textual pointer,
  never `@import`**, so both harnesses read the pointer identically and open
  the file the same way.

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
*target*, referencing the path in its guidance pointer. This mirrors the
`git-commit-attribution` consumer-declared spec mount already cited below.

**No absent-mount detection.** No Feature warns when the mount is missing. A
directory test at the target cannot distinguish a landed bind from any other
directory occupying the path, and a mount-point probe would report a failure for
instructions that arrived by some route other than a bind. A container without
the mount still starts, and each harness's always-on file already instructs it
to say the referenced detail is unavailable rather than invent it. Decided
(owner, 2026-08-05, in session).

**Read-only.** The instructions are read, never written, so the mount is
`readonly`: no approved/full-access command in any harness can alter the shared
**`instructions/` files** through this mount. (The `ssh` Feature's `known_hosts`
`bind,readonly` is the in-repo precedent.) This protects only the `instructions/`
subset; the pre-existing `CLAUDE.md`/`AGENTS.md` bind mounts remain plain
writable `bind` and are deliberately left unchanged — hardening them is
pre-existing plumbing outside this PR's scope. Implementation verifies the
configuration it owns — that the consumer `devcontainer.json` declares the
mount with the correct source, target, and `readonly` flag — and assumes Docker
enforces a correctly declared read-only bind rather than re-testing that
enforcement. Decided (owner, 2026-07-26:
https://github.com/hube/devcontainer/pull/55#discussion_r3651595630).

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

1. the shared canonical file reaches *N* under its instruction filename (e.g.
   `GEMINI.md`) via a **consumer-declared** mount — the host source
   `~/.claude/CLAUDE.md` is Claude-layout-specific, so per the same
   mount-ownership convention as the instructions mount, *N*'s Feature must not
   declare it. The Feature owns only its stable container target. (The existing
   Claude and Codex file mounts are Feature-declared — the Codex Feature
   hardcodes the `~/.claude/CLAUDE.md` source today — and remain grandfathered
   pre-existing plumbing, unchanged like their writable `bind` mode; new
   Features do not repeat the leak); and
2. **no new instructions mount is needed** — the single consumer-declared
   `~/.agents/instructions` mount already serves every harness in the container.
   *N*'s Feature owns only the target-path reference.

Content stays neutral; add a per-harness subsection only where dispatch
mechanics differ.

## Architecture by repo

### `hube/claude-home` (content)

- **`CLAUDE.md`** — fold the lean always-on discipline into existing sections:
  design-doc guidance gains rigor-levels-are-inputs + the altitude step +
  defer-to-fixture; "Scope of a code review" gains meets-not-exceeds,
  over-engineering-is-a-defect, and don't-infer-or-reverse; the escalation rule
  gains the same-mechanism breaker as the matched complement to the existing
  contested-twice rule; the review-feedback guidance gains the
  exchange-proportionality trio; the PR workflow guidance gains the
  change-sequencing guardrails; and a plain-text pointer to
  `~/.agents/instructions`.
- **`instructions/rigor-levels.md`** (new) — the full vocabulary reference,
  breaker counting mechanics (including the breaker boundary), ratification
  triggers, checkpoint cadence, thresholds, and brainstorming elicitation
  prompts.
- **`instructions/review-dispatch-scope.md`** (new) — the canonical reviewer
  scope block, ported from fin's current `design-review-dispatch.md` with
  **six adaptations**: assurance→rigor renaming; retargeting the block's
  fin-repo-local cross-references — the preamble's `docs/designs/CONVENTIONS.md`
  and `docs/prompts/reader-proxy-review-dispatch.md` citations become the
  neighboring `~/.agents/instructions/rigor-levels.md` and
  `~/.agents/instructions/reader-proxy-review-dispatch.md`, and rule 9's
  pointer to "this repository's `AGENTS.md`" proportionality section becomes
  the shared always-on `CLAUDE.md`/`AGENTS.md` (an arbitrary project's own
  `AGENTS.md` does not carry that section); dropping the preamble's
  "for this repository" qualifier, since the block now serves every consumer
  repo, not one; adding a header sentence clarifying that "this block" means
  the content between the `---` separators, not the header paragraph itself;
  narrowing rule 6's "author/orchestrator" to "author"; and dropping rule 9's
  trailing rationale sentence ("It is named here rather than copied because a
  second copy would drift from the first"). The port keeps
  its numbered scope rules (meets-not-exceeds with
  the no-severity rationale, over-engineering with equal credit for removable
  machinery, don't-infer-or-reverse, provisional-levels-are-questions,
  defer-to-fixture, churn disclosure, proportioned findings,
  remediated-error-is-closed, exchange binding) plus the clause making
  level-dependent rules inert for artifacts no design governs. Included
  verbatim in every design and code review dispatch — code reviews measure the
  implementation against the governing design's Decided levels — and never in
  a reader-proxy dispatch.
- **`instructions/reader-proxy-review-dispatch.md`** (new) — the canonical
  reader-proxy block, ported from fin: the four reporting categories, the
  orchestrator's no-further-context rule, "cannot complete" as a finding not a
  blocker, and refuse-context-out-loud. The port carries **one adaptation**: a
  header sentence naming what "this block" is — the content between the `---`
  separators, excluding the header paragraph and the orchestrator note — plus
  the closing `---` that sentence refers to, so an assembler transcluding the
  block knows where it ends. Decided (owner, 2026-08-05, in session).
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
  stable container target `~/.agents/instructions`, referencing it in the shared
  guidance pointer. Neither adds a lifecycle hook.
- Feature `NOTES.md` documents the consumer mount users must add, per the repo's
  docs conventions.

### Rollout ordering

The ordering gate is **host state, not repository merge order**: Docker
resolves the mount source `${localEnv:HOME}/.claude/instructions` from the
deployed host config, so merging claude-home's `instructions/` to `main`
creates nothing on a host until that change is deployed into the checkout
backing `~/.claude`. The gate before a devcontainer rebuild consumes the new
consumer mount is therefore that **`~/.claude/instructions` exists on the
host**. Sequence: land claude-home (the `instructions/` directory and its
gitignore allow-list); deploy it to the host and verify the host directory
exists — folded into the same implementation-time step that re-confirms
deployed-`CLAUDE.md` parity (Open questions); only then land the
devcontainer change (the consumer mount).

The gate is load-bearing because Docker rejects a bind mount whose host
source does not exist, breaking container startup outright. (Method: with
`/nonexistent-path-129fd48b` first confirmed absent via `test ! -e`,
`docker run --rm --mount
type=bind,source=/nonexistent-path-129fd48b,target=/probe alpine:latest true`
against the local daemon fails with `invalid mount config for type "bind":
bind source path does not exist`. That is `--mount` semantics — the older `-v` syntax
would instead auto-create a missing host path, a difference Docker's
bind-mount documentation records — and it is the applicable semantics here
because `devcontainer.json` `mounts` values take "the same values as the
Docker CLI `--mount` flag" per the Dev Containers JSON reference.) The
reverse order is safe: a present-but-unmounted `instructions/` directory on
the host is inert. Feature `NOTES.md` documents that the host directory must
exist before the consumer mount is declared.

## Rejected alternatives

### Keep "assurance levels" concrete (durability-only)

Rejected. Porting fin's ladder verbatim as the canonical global vocabulary
frames everything around failure/durability/audit; other dimensions (perf,
security, compatibility) bolt on awkwardly. Generalizing to "rigor levels" with
named per-dimension ladders keeps fin's ladder intact as one instantiation while
covering the rest.

### Encode the dispatch blocks as skills

Rejected. The blocks' defining use is **verbatim transclusion into a
*subagent's* prompt**; the consuming reviewer inherits nothing and (per the
superpowers `SUBAGENT-STOP` rule) ignores skill bootstrapping, so each block must
exist as retrievable literal text regardless. A skill wrapper adds a layer
without adding capability and muddies the verbatim boundary with frontmatter and
meta-instructions. A file whose entire content is the block transcludes cleanly.
Discoverability is served instead by the always-on `CLAUDE.md` pointing at the
files as the canonical source.

### Mirror fin's split on the host tree with no plumbing change

Rejected. The single-file cross-harness channel means host supporting files
never reach containers, and `@import` diverges between Claude Code and Codex. The
split only transports if a directory mount is added — which this design does.

### Inline everything into the one shared file (no plumbing change)

Rejected as the whole answer, though its always-on half is adopted. Inlining the
bulk reference and the verbatim blocks would bloat the always-loaded file and
lose the clean copy-from-a-file model for the dispatch blocks. The hybrid keeps
the always-on discipline inline and moves only the bulk/verbatim material to the
mounted directory.

### No fixed thresholds

Rejected. Qualitative-only guidance ("a few rounds", "periodically") is not
actionable out of the box. fin's 3-round breaker and 10-round checkpoint ship as
concrete defaults.

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

- **Confirm deployed `CLAUDE.md` parity at implementation time.** The deployed
  `~/.claude/CLAUDE.md` must match claude-home's tracked copy before the new
  inline discipline and pointer ship. Because the deployed file is a mount of
  the host checkout, merging claude-home does not change it; parity must be
  confirmed on the host, not assumed. This is the same host-deployment step the
  rollout gate above requires for `~/.claude/instructions`.

## Related

- `hube/fin#5` — the repo-local original this generalizes.
- `hube/fin#1` — the review loop whose ratchet motivated fin#5.
- `hube/fin#48` (landed in fin PR #54) — the change-sequencing guardrails and
  reader-proxy dispatch; with the fin#47 review, the source of the post-fin#5
  guidance this design also lifts.
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
- 2026-07-23: Owner decision (devcontainer#55). Direct-host sessions are out of
  scope — the mechanism is devcontainer-only. Dropped the round-4 host symlink,
  recorded direct-host as a Non-goal with the owner's decision link, and closed
  the parity open question.
- 2026-07-23: Review round 5 (devcontainer#55). Narrowed the read-only rationale
  to the `instructions/` subset it actually protects; noted the pre-existing
  `CLAUDE.md`/`AGENTS.md` mounts remain writable `bind` and are out of scope
  (claim precision, not added mechanism).
- 2026-08-03: Owner review round (devcontainer#55). Addressed the four inline
  comments: rigor-table placement is now stated as proximity to the design's
  scope statements rather than assuming a Non-goals section; the
  no-severity/no-prescribed-fix rule carries its rationale; brainstorming
  elicitation is generalized across dimensions with durability as the worked
  example; read-only mount verification is scoped to the configuration we own,
  assuming Docker's enforcement (owner decision). Per the owner's direction,
  harvested fin's post-fin#5 guidance (fin#48 / fin PR #54 and the current
  `AGENTS.md`, `CONVENTIONS.md`, and dispatch prompts): the breaker boundary
  (owner-decision-attached findings are fixed, not escalated),
  review-exchange proportionality, proportioned findings and
  remediated-error-closed in the scope block, equal credit for removable
  machinery, ratification-may-take-longer, the change-sequencing guardrails,
  and the reader-proxy dispatch as a second verbatim instructions file.
- 2026-08-03: Review round 7 (devcontainer#55, Claude + Codex reviewers). The
  scope-block port now names its **second adaptation**: fin-repo-local
  cross-references retarget to the `~/.agents/instructions/` files and the
  shared always-on file (renaming alone leaves them dangling). Added the
  rollout-ordering section (claude-home lands `instructions/` before the
  consumer mount — Docker rejects a bind whose host source is missing,
  verified against the local daemon). Deleted the open question's runtime
  mount-landing check (contradicted the owner's configuration-only
  verification boundary). Future-harness guidance-file mounts are
  consumer-declared (the Claude-layout source must not leak into new
  Features; existing Claude/Codex mounts grandfathered). Restored fin's
  "a design specifies what it guarantees" sentence to the defer rule;
  pluralized the dispatch-block rejected alternative; dropped the
  non-load-bearing "roughly half" fraction and the "patch-stable"
  future-version characterization from live text (changelog history
  retained).
- 2026-08-04: Review round 8 (devcontainer#55). Two formatting corrections in
  place: re-wrapped the fin#1 context paragraph; fixed the grandfathering
  parenthetical's punctuation.
- 2026-08-04: Review round 9 (devcontainer#55, Codex reviewer). Rollout
  ordering now gates on **host state** (deploy claude-home's `instructions/`
  to the host and verify it exists before the devcontainer change lands),
  not repository merge order, folded into the existing implementation-time
  parity step. The Docker probe records its method inline (exact `--mount`
  command and error, the `-v` auto-create distinction ruled out, and the Dev
  Containers JSON reference tying `mounts` to `--mount` semantics).
- 2026-08-04: Review round 10 (devcontainer#55, Codex reviewer). The probe
  method's `<missing>` placeholder is replaced with the actual absent path
  used, its absence pre-checked via `test ! -e`, making the recorded command
  executable as written (probe re-run to confirm).
- 2026-08-05: Review round 11 (devcontainer#55, three reviewers). Synced the
  design with owner-directed guidance changes made after it merged: corrected
  the `review-dispatch-scope.md` port's adaptation count from two to six
  (assurance→rigor renaming; cross-reference retargeting; dropping the
  preamble's "for this repository" qualifier; adding a header sentence
  clarifying what "this block" refers to; narrowing rule 6's
  "author/orchestrator" to "author"; dropping rule 9's trailing rationale
  sentence); removed the Thresholds section's and the "No fixed thresholds"
  rejected alternative's claim that the defaults ship with an explicit "tune
  per project" note, since the note was removed under owner direction; and
  recorded the owner's 2026-08-05 ruling that reader-proxy findings are
  advisory while effectiveness data is collected.
- 2026-08-05: Owner decision on `hube/claude-home#9`. Option B: the churn
  breaker's trigger stays recurrence alone (the accretion-only narrowing an
  implementation round introduced is reverted); its remedy is now scoped to
  the cause of the recurrence rather than limited to the three machinery
  options, and recurrence on a claim is self-authorising (delete and
  disclose) where recurrence on a mechanism still waits for the owner.
- 2026-08-05: Propagated the Option B decision above to the two places in
  "The churn tripwire" section that still described the breaker in terms of
  the reverted accretion-only reading. The trigger bullet's parenthetical now
  names agreement-churn/accretion as the trigger's motivating case rather
  than the trigger itself, and its remedy clause points at the **Remedy
  scoped to cause** paragraph instead of restating the three machinery
  options as the whole memo; the thresholds paragraph now refers to
  repetition rather than accretion.
- 2026-08-05: Owner decision (devcontainer#59, in session). The absent-mount
  postStart warning is dropped from both harness Features. A directory test at
  the target cannot distinguish a landed bind from any directory occupying the
  path, and a mount-point probe would misreport instructions arriving by any
  other route; the always-on guidance already tells each harness to say the
  referenced detail is unavailable. Features now own only the container target
  path.
- 2026-08-05: Review round 1 (devcontainer#59, Claude reviewer). Reconciled the
  design against the guidance as shipped in claude-home `859cccd` rather than
  patching the two differences reported: the counting-mechanics paragraph now
  says the **author** owns the count and that blocked-mechanism findings are
  collected into **an options memo**; deleted the dangling reference to "the
  three machinery options above", a list this document never contained; recorded
  the reader-proxy port's one owner-approved adaptation and the `in session`
  status-marker form; and deleted the Open questions claim that the deployed
  `CLAUDE.md` is byte-identical to the tracked copy, which merging claude-home
  did not make true.
