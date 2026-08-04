# Rigor levels and anti-ratchet review discipline — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the rigor-levels vocabulary and anti-ratchet review discipline as
always-on, harness-neutral agent guidance — inline discipline in the shared
`CLAUDE.md`/`AGENTS.md`, bulk reference and verbatim dispatch blocks in a shared
`instructions/` directory reachable from every harness at `~/.agents/instructions`.

**Architecture:** Two repositories, in order. `hube/claude-home` holds the
content: the always-on inline rules in `CLAUDE.md`, plus three new files under
`instructions/`. `hube/devcontainer` holds the plumbing: one consumer-declared,
read-only bind mount exposing that directory at the harness-neutral container
path `~/.agents/instructions`, and a postStart warning in each harness Feature
for when the mount is absent. A host-state gate sits between them.

**Tech Stack:** Markdown (agent instructions), Dev Container Feature manifests
(JSON with comments), Bash postStart hooks, Bash/Python test harnesses in the
style already used by `local-features/github-cli-config` and
`local-features/codex`.

**Source design:** `docs/designs/2026-07-22-rigor-levels-anti-ratchet-design.md`
(merged in `hube/devcontainer#55`, merge commit `029d6f8`). The design is
settled; this plan implements it and does not revisit its decisions.

---

## Global Constraints

- **Two repositories, two PRs, in this order:** `hube/claude-home` (Phase A)
  first, then `hube/devcontainer` (Phase B). The devcontainer PR must not merge
  until the host gate in Phase G is confirmed.
- **Mandatory worktree isolation.** Every repository edited needs its own linked
  worktree owned by this exact task or resumed session. Never modify a primary
  checkout. The `hube/devcontainer` worktree already exists at
  `/workspaces/agent-devcontainer/devcontainer/.claude/worktrees/calm-napping-turtle`
  (branch `worktree-calm-napping-turtle`, Claude Code native lock). A
  `hube/claude-home` worktree must be created in Task A0.
- **Harness-neutral content.** Everything written into `CLAUDE.md` and
  `instructions/` is read verbatim by Claude Code (as `~/.claude/CLAUDE.md`) and
  by Codex (as `~/.codex/AGENTS.md`). No `@import` may be load-bearing — Codex
  reads `AGENTS.md` wholesale and does not expand `@path`. All cross-file
  references are plain textual pointers.
- **The neutral pointer path is exactly `~/.agents/instructions`** — never
  `~/.claude/instructions` or `~/.codex/instructions` in any text a harness reads.
- **The mount source is exactly `${localEnv:HOME}/.claude/instructions`** and the
  target exactly `/home/${localEnv:USERNAME:devcontainer}/.agents/instructions`,
  read-only, declared **once** by the consumer, never by a Feature.
- **postStart never blocks container start.** Every hook added here exits 0 on
  every path and writes problem → consequence → remedy, in that order, to stderr
  (`docs/feature-authoring.md`).
- **Commit trailers.** Every commit ends with a contiguous trailer block, no
  blank line inside it:

  ```
  Harness: Claude Code
  Harness-Version: <exact output of `claude --version`>
  Model: <model id that served the turn>
  Skills: <skills used, comma-separated; omit the line when none>
  Co-Authored-By: <model display name> <noreply@anthropic.com>
  ```

  Verify after each commit with
  `git log -1 --pretty=%B | git interpret-trailers --parse`.
- **No design changes.** If something in the design looks wrong, report it; do
  not edit `docs/designs/2026-07-22-rigor-levels-anti-ratchet-design.md`.

---

## File Structure

### Phase A — `hube/claude-home`

| File | Responsibility |
|---|---|
| `.gitignore` (modify) | Allow-list `instructions/` so the new files are tracked at all |
| `instructions/rigor-levels.md` (create) | The bulk vocabulary reference: levels-as-inputs, status markers, default floor, named ladders, table format, breaker counting mechanics, ratification triggers, checkpoint cadence, thresholds, elicitation prompts |
| `instructions/review-dispatch-scope.md` (create) | The verbatim reviewer scope block, transcluded into every design and code review dispatch |
| `instructions/reader-proxy-review-dispatch.md` (create) | The verbatim reader-proxy dispatch block |
| `CLAUDE.md` (modify) | The lean always-on discipline plus the plain-text pointer to `~/.agents/instructions` |

### Phase B — `hube/devcontainer`

| File | Responsibility |
|---|---|
| `.devcontainer/local-features/claude/devcontainer-feature.json` (modify) | Repair malformed JSON (pre-existing); declare `postStartCommand` |
| `.devcontainer/local-features/claude/install.sh` (modify) | Copy `bin/` into the container user's home with executable mode |
| `.devcontainer/local-features/claude/bin/devcontainer-feature/claude/postStartScript.sh` (create) | Warn when `~/.agents/instructions` is absent |
| `.devcontainer/local-features/claude/NOTES.md` (create) | Document the consumer mount and the host prerequisite |
| `.devcontainer/local-features/claude/test/test-poststart.sh` (create) | Cover the hook's three paths |
| `.devcontainer/local-features/claude/test/test-consumer-mount.sh` (create) | Assert the consumer `devcontainer.json` declares source, target, and read-only |
| `.devcontainer/local-features/codex/devcontainer-feature.json` (modify) | Declare `postStartCommand` |
| `.devcontainer/local-features/codex/bin/devcontainer-feature/codex/postStartScript.sh` (create) | Warn when `~/.agents/instructions` is absent |
| `.devcontainer/local-features/codex/NOTES.md` (modify) | Document the consumer mount and the host prerequisite |
| `.devcontainer/local-features/codex/test/test-poststart.sh` (create) | Cover the hook's three paths |
| `.devcontainer/local-features/codex/test/test-feature-config.py` (modify) | Assert the new `postStartCommand` value |
| `.devcontainer/devcontainer.json` (modify) | Declare the consumer mount once, read-only |
| `README.md` (modify) | Link the new Claude feature notes |

---

## Phase A — `hube/claude-home` (content)

### Task A0: Create the claude-home worktree

**Files:** none edited; creates a worktree.

- [ ] **Step 1: Confirm the repository and its clean state**

```bash
git -C /workspaces/agent-devcontainer/claude-home remote -v
git -C /workspaces/agent-devcontainer/claude-home status --short
git -C /workspaces/agent-devcontainer/claude-home fetch origin main
```

Expected: `origin` is `git@github.com:hube/claude-home.git`. Note any dirty
files — they belong to the user and must not be staged, committed, or reverted.

- [ ] **Step 2: Confirm `.worktrees` is ignored before creating one there**

```bash
git -C /workspaces/agent-devcontainer/claude-home check-ignore -q .worktrees/.probe && echo IGNORED || echo NOT-IGNORED
```

Expected: `IGNORED`. claude-home's `.gitignore` excludes everything with `*` and
allow-lists, so this passes. If it prints `NOT-IGNORED`, **stop and report** —
do not edit `.gitignore` from the primary checkout to make it pass.

- [ ] **Step 3: Create and lock the worktree**

```bash
cd /workspaces/agent-devcontainer/claude-home
git worktree add .worktrees/rigor-levels-content -b implement/rigor-levels-instructions origin/main
git worktree lock --reason \
  "owner=claude-code; session=${CLAUDE_CODE_SESSION_ID}; task=implement rigor-levels claude-home content; created=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  .worktrees/rigor-levels-content
git worktree list --porcelain | grep -A3 rigor-levels-content
```

Expected: the `locked` line shows the reason above. If creation or locking
fails, **stop and report the exact failure, its consequence, and the remedy** —
do not fall back to the primary checkout.

- [ ] **Step 4: Re-confirm deployed `CLAUDE.md` parity (the design's open question)**

```bash
diff -u ~/.claude/CLAUDE.md /workspaces/agent-devcontainer/claude-home/CLAUDE.md && echo IDENTICAL
```

Expected: `IDENTICAL`. This is the design's one open question — the deployed
`~/.claude/CLAUDE.md` must match claude-home's tracked copy before the new
inline discipline ships. If they differ, **stop and report the diff**; editing
the tracked copy while the deployed one has diverged would silently drop the
host's changes on the next deploy.

---

### Task A1: Track `instructions/` and add the rigor-levels reference

**Files:**
- Modify: `<claude-home-worktree>/.gitignore`
- Create: `<claude-home-worktree>/instructions/rigor-levels.md`

**Interfaces:**
- Produces: the path `instructions/rigor-levels.md`, referenced by
  `review-dispatch-scope.md` (Task A2) and `CLAUDE.md` (Task A4) as
  `~/.agents/instructions/rigor-levels.md`.

- [ ] **Step 1: Write the failing check**

claude-home has no test framework. The check is `git check-ignore`, which must
report the new path as **not** ignored. Run it first to see it fail:

```bash
cd <claude-home-worktree>
mkdir -p instructions && touch instructions/rigor-levels.md
git check-ignore -q instructions/rigor-levels.md && echo "IGNORED (expected failure)" || echo "TRACKED"
```

Expected now: `IGNORED (expected failure)` — the repo's `*` exclude swallows it.

- [ ] **Step 2: Add the allow-list entries to `.gitignore`**

Insert directly after the `!.github` / `!.github/**/*` pair, keeping the file's
"Directories to include" grouping:

```gitignore
!instructions
!instructions/**/*
```

- [ ] **Step 3: Re-run the check**

```bash
cd <claude-home-worktree>
git check-ignore -q instructions/rigor-levels.md && echo "IGNORED" || echo "TRACKED"
git status --short instructions/
```

Expected: `TRACKED`, and `git status` lists `?? instructions/rigor-levels.md`.

- [ ] **Step 4: Write `instructions/rigor-levels.md`**

Write this exact content:

````markdown
# Rigor levels

Shared reference for owner-controlled rigor levels and the anti-ratchet review
discipline. The always-on rules live in the shared agent instructions
(`~/.claude/CLAUDE.md` for Claude Code, `~/.codex/AGENTS.md` for Codex — the
same file under two names). This file holds the vocabulary, the counting
mechanics, and the elicitation prompts those rules refer to.

Companion files in this directory:

- `review-dispatch-scope.md` — the reviewer scope block, included verbatim in
  every design and code review dispatch.
- `reader-proxy-review-dispatch.md` — the reader-proxy dispatch block.

## Levels are owner inputs, not draft properties

A **rigor level** states how much protection a mechanism area must deliver —
and, by omission, what it need not. Levels are inputs the owner controls, not
properties a draft accretes.

The asymmetry cuts both ways: a **weak level caps** machinery (findings
demanding more are out of scope), and a **strong level authorizes** it (rigor
belongs where the owner placed it). Making the strong areas explicit is as much
the point as bounding the weak ones.

Rigor applies to any dimension with an owner-chosen tolerance — durability,
performance budgets, security posture, compatibility guarantees, test rigor —
not only failure handling.

## Status markers

- `provisional (author-proposed)` — a standing question, not a settled input.
  The first review round must address it explicitly (confirm or contest), and
  every later round re-surfaces it as a calibration question until the owner
  ratifies or revises it. Ratification may take longer than one round, and the
  level stays provisional until it happens. Against a provisional level, a
  mechanism/level mismatch is a **calibration question routed to the owner**,
  never a defect with a prescribed fix.
- `Decided (owner, YYYY-MM-DD: link)` — a settled input. The review scope rule
  applies. Link the artifact where the owner made the decision — a PR comment,
  a review, an issue. When the decision was made in conversation and no artifact
  exists, write `Decided (owner, YYYY-MM-DD, in session)` rather than dropping
  the marker.

Levels are revised later only as a marked owner decision, never by drift.

## Default floor

Absent any stated level, the default is the **weakest**: primary data must never
be damaged or lost; everything else is presumed re-doable until the owner says
otherwise.

The default is weak by design — strengthening must be a deliberate owner
decision that knowingly buys machinery. The alternative default (the strictest
defensible reading of whatever invariants a draft happens to state) turns every
stated invariant into a load-bearing requirement nobody chose, and each
mechanism serving it into fresh review surface.

## Named ladders

Levels are stated as **required outcomes in prose**, not picks from one fixed
enum. This file hosts a named ladder per dimension, ordered weakest first, for
comparison; an area may combine rungs.

A dimension gets a named ladder **when a real design needs one**, not
speculatively.

### Durability / failure

1. **Re-doable** — failure is recovered by discarding partial state and
   re-running.
2. **Protected** — primary data and committed outputs are never damaged,
   whatever else is lost.
3. **Recorded** — outcomes leave durable, committed evidence a human judges.
4. **Mechanically verified** — a machine checks the property every run.
5. **Independently verified** — the check runs through a path sharing no code
   (or no author) with what it checks.

## Format

One row per mechanism area, declared in the design's own "Rigor levels"
section:

| Area | Level | Status |
|---|---|---|
| Crash recovery | Re-doable: primary data and committed outputs are never damaged; all other partial state is discarded and the operation re-run | Decided (owner, YYYY-MM-DD: link) |
| Audit trail | Owner-judged over committed evidence; adversarial reconstruction is a non-goal | provisional (author-proposed) |

Place the section with the design's scope statements — whatever the document's
structure calls them — so levels read as owner inputs rather than properties
discovered later in the draft. In documents following the Goals/Non-goals
convention, that means directly after Non-goals.

## Churn circuit-breaker: counting mechanics

The breaker fires when **three consecutive review rounds** produce findings
confined to the same section or mechanism.

- A **round** is one aggregated review cycle against a single named head.
  Concurrent reviewers at the same head are one round; a re-review after new
  commits is the next.
- Recurrence is counted **per mechanism**, even when a cycle also draws
  unrelated findings.
- The **author/orchestrator owns the count**. A reviewer only *discloses*
  recurrence; it does not decide that the breaker fires.
- The breaker blocks **only the churning mechanism**. Reviews and fixes
  elsewhere continue, and further findings against a blocked mechanism are
  collected into its memo rather than answered — so an autonomous cycle keeps
  moving and the owner reviews all accumulated blockers at once.
- Resume a blocked mechanism only after the owner picks from its memo.

**False positives.** The breaker fires on *repetition on the same ground*, not
on breadth. Deliberate multi-angle review that sweeps many mechanisms once is
not churn; three rounds circling the *same* mechanism is.

**Boundary.** The breaker routes **unresolved requirement questions** to the
owner. It is not a mechanism for declining an instruction the owner has already
given: a round whose finding arrives with the owner's decision attached is
**fixed, not escalated**, even when it is the third consecutive round confined
to that mechanism.

## Ratification triggers

A provisional or unstated level must be put to the owner when either occurs:

- the design gains its first mechanism that exists **only** to serve that
  level; or
- the churn circuit-breaker fires.

## Owner checkpoint cadence

**Autonomous and unattended review loops only.** In attended work this rule is
inert.

Post a compressed delta-and-open-questions summary to the owner every **10
review rounds**, or immediately whenever **all** review activity is blocked (for
example, every open finding sits behind a churn breaker). Do not rely on the
owner noticing a spiral; schedule the checkpoint.

## Thresholds

The breaker's **3 consecutive same-mechanism rounds** and the checkpoint's **10
rounds** are concrete defaults, carried forward by owner decision. They are a
chosen starting point, not an empirically measured optimum — tune them per
project.

## Brainstorming: elicit levels first

When brainstorming any feature that touches a dimension with owner-chosen
rigor, elicit that dimension's levels **before designing mechanisms**. Whatever
the dimension, the questions are about the owner's tolerance, not the design —
what outcome must hold, what may be lost or degraded, who consumes the
evidence, how often the scenario arises — so they are answerable on day one.

Record the answers in the draft as levels marked `provisional
(author-proposed)`.

The durability/failure dimension's questions are the worked example:

- If this fails midway, is re-doing the whole operation acceptable recovery?
- What must never be lost or damaged, even in a crash? (Usually a short list;
  everything off it is presumed re-doable.)
- Who consumes the audit trail — a human, a program, a future auditor? Must its
  conclusions be *recomputable*, or *judged from evidence*?
- How often does this run, and is a human present when it does?

Other dimensions derive their elicitation questions the same way — from the
owner's tolerance, not from the draft's invariants.
````

- [ ] **Step 5: Verify the file is tracked and the pointer paths are neutral**

```bash
cd <claude-home-worktree>
git status --short instructions/
grep -n "\.claude/instructions\|\.codex/instructions\|@import\|@~/" instructions/rigor-levels.md
```

Expected: `git status` lists `?? instructions/rigor-levels.md`; the `grep`
prints nothing (exit 1) — no harness-specific instructions path and no
`@import` appears in the file.

- [ ] **Step 6: Commit**

```bash
git add .gitignore instructions/rigor-levels.md
git commit   # message below
git log -1 --pretty=%B | git interpret-trailers --parse
```

Message subject: `Add the rigor-levels shared reference`. Body: one paragraph
explaining that claude-home's `*`-exclude gitignore requires the
`!instructions` allow-list or the file is silently untracked. Then the trailer
block from Global Constraints.

---

### Task A2: Port the reviewer scope block

**Files:**
- Create: `<claude-home-worktree>/instructions/review-dispatch-scope.md`

**Interfaces:**
- Consumes: `instructions/rigor-levels.md` (Task A1) — referenced as
  `~/.agents/instructions/rigor-levels.md`.
- Produces: the path `instructions/review-dispatch-scope.md`, referenced by
  `CLAUDE.md` (Task A4) as `~/.agents/instructions/review-dispatch-scope.md`.

**Source:** `hube/fin` `docs/prompts/design-review-dispatch.md` at commit
`5d9534aae16d5ce7f7869ceea3e5109d4c94ca88`. Two adaptations, both mandated by
the design: assurance→rigor renaming, and retargeting fin-repo-local
cross-references. Everything else is a verbatim port.

- [ ] **Step 1: Fetch the source and record what you are adapting**

```bash
gh api repos/hube/fin/contents/docs/prompts/design-review-dispatch.md \
  --jq '.content' \
  -H "Accept: application/vnd.github+json" \
  -f ref=5d9534aae16d5ce7f7869ceea3e5109d4c94ca88 | base64 -d > /tmp/fin-design-review-dispatch.md
grep -n "assurance\|CONVENTIONS.md\|docs/prompts\|this repository" /tmp/fin-design-review-dispatch.md
```

Expected: the grep lists exactly the lines the adaptations below touch. If it
lists a line the adaptation list does not cover, **stop and report** — the
source has changed since this plan was written.

- [ ] **Step 2: Write `instructions/review-dispatch-scope.md`**

Write this exact content (the fin block with both adaptations applied):

````markdown
# Review dispatch: standing scope addendum

**Canonical source.** This block is included **verbatim** in every design and
code review dispatch prompt, after the list of settled decisions, whether the
dispatch is written by hand or assembled by another agent. It is **not**
included in a reader-proxy dispatch
(`~/.agents/instructions/reader-proxy-review-dispatch.md`), which carries no
context beyond its own prompt and the documentation under review. For code
reviews, the rigor levels come from the governing design. Dispatched reviewers
inherit nothing; the prompt is the only thing that binds them.

---

Where the artifact under review is governed by a design, that design declares
**rigor levels** (its "Rigor levels" section; conventions in
`~/.agents/instructions/rigor-levels.md`; where the design declares none, the
default floor applies: primary data must never be damaged or lost, everything
else is presumed re-doable). Where the artifact is governed by **no design** — a
tooling, CI, or conventions change no design covers — the level-dependent rules
(1, 2, and 4) are inert; the remaining rules and the standing rules at the foot
of this block still apply. Scope rules, in addition to the settled-decisions
list above:

1. **Meets, not exceeds.** Verify the design MEETS each Decided rigor level. A
   finding that it fails to EXCEED a Decided level is out of scope as a defect.
   If such a gap looks unintended, raise it as a **one-line calibration question
   addressed to the owner**, with no prescribed fix and no severity label — a
   prescription presupposes the answer (that the level should rise), and a
   severity label puts the question in the findings queue, creating closure
   pressure to add mechanism before the owner has decided.
2. **Over-engineering is a defect.** A mechanism that defends against a scenario
   the Decided levels or Non-goals exclude is a valid Important finding —
   recommend **deletion**, not refinement. You get equal credit for finding
   removable machinery as for finding missing machinery.
3. **Don't infer scope or reverse a decision.** When it is unclear whether a
   Decided level even *applies* to the mechanism under review, or when an
   over-engineering/deletion finding would reverse a *different* settled owner
   decision, do not resolve it yourself: raise a **calibration or
   decision-conflict question to the owner** — no severity, no prescribed fix —
   and leave the mechanism in place until the owner reconciles the records.
   Inferring applicability is how machinery gets approved that no level
   authorized; deleting on inference is how a settled decision gets silently
   reversed.
4. **Provisional levels are questions, not walls.** Against a level marked
   `provisional`, a mechanism/level mismatch is a calibration question for the
   owner, not a finding. Confirming or contesting provisional levels is an
   explicit deliverable of a first-round review.
5. **Prefer deferral for implementation-level correctness.** Where a design
   states a guarantee whose satisfaction turns on code-level detail — I/O
   ordering, concurrency windows, exact library or platform semantics, anything
   whose truth is established by running code — prefer the disposition "defer to
   implementation with a required fixture" over prescribing prose mechanism —
   unless the stated guarantee is itself unmeetable, which is a finding.
6. **Churn awareness.** If your findings are confined to the same section or
   mechanism a previous round's findings addressed, say so explicitly in the
   review so the author's circuit-breaker can fire. A round is one aggregated
   cycle against a named head; the author/orchestrator owns the recurrence
   count, so disclosing is all that is asked of you.
7. **Proportion the vehicle to the consequence.** Before raising a finding, ask
   what changes if it is fixed; the answer sets the vehicle, and needs stating
   only where the finding does not make it obvious. A defect whose whole remedy
   is a correction in place — this number, this reference, this word, wherever
   it landed — is one line naming the correction, every artifact that must
   change, and its own disposition ("counted from the module: 14, not 13; also
   in issue #12's carry-forward — correct both; not blocking"), never its own
   section with evidence. The trigger is the shape of the remedy, not the reach
   of the defect: a miscount that reached a tracking issue and a carry-forward
   is still a correction in place — corrected in more places, not a finding that
   earns a section. What a section would add — a quoted excerpt, a stated cause,
   a paragraph on why it was raised — changes nothing about the correction, and
   that apparatus is what this rule removes. Compress the report, not the
   verification: the disposition is itself an empirical claim, so establish it
   as you would any other and state the method inside the same line. Look for
   the claim in every durable artifact — code, design, docstring, tracking
   issue, PR body, carry-forward — before asserting where it landed; a repo grep
   answers "did this reach the code", not "did this reach a durable artifact",
   and finding more places lengthens the list of places to correct, not the
   report. Format sets the register: a finding presented with a table invites a
   table back, and a correction that costs more to argue than the error costs to
   leave is a net loss even when it is right. This does not license silence — a
   false claim in a durable artifact is still reported; it constrains only how
   much apparatus the report carries.
8. **A remediated error is closed.** Once a false claim has been corrected in
   every artifact carrying it — checked against the same list rule 7 enumerates,
   not assumed — the correction closes it. A guard does not reopen it: if one is
   worth building, propose the guard in one line as a change to a named artifact
   and stop there — nobody has to agree on the cause to build it. State a
   *cause* at most once; if the cause is contested, the correction stands and
   the thread ends. This binds a reviewer receiving a correction to its own
   finding exactly as it binds an author receiving a finding.
9. **The exchange itself is bound too.** Your replies are governed by the
   "Review exchanges: proportionality" section of the shared always-on agent
   instructions (`~/.claude/CLAUDE.md` for Claude Code, `~/.codex/AGENTS.md` for
   Codex — the same file under two names); read it before answering a correction
   to one of your own findings. It is named here rather than copied because a
   second copy would drift from the first.

Existing standing rules remain in force: review the work and the claims it
makes, not the sufficiency of rationale behind settled decisions; a finding must
be actionable (a defect, a false claim, or a gap an implementer would hit),
proportioned per rule 7; test the claims the artifact makes — never manufacture
evidence for its conclusions; state the method for any empirical claim and name
the benign explanation you ruled out, at the scale rule 7 sets; a review with no
findings is a valid review.

---
````

- [ ] **Step 3: Verify the adaptations landed and nothing dangles**

```bash
cd <claude-home-worktree>
grep -n "assurance\|docs/designs/CONVENTIONS.md\|docs/prompts/\|this repository" instructions/review-dispatch-scope.md
grep -c "^[0-9]\." instructions/review-dispatch-scope.md
grep -n "~/.agents/instructions/rigor-levels.md\|~/.agents/instructions/reader-proxy-review-dispatch.md" instructions/review-dispatch-scope.md
```

Expected: the first grep prints nothing (exit 1) — no fin-repo-local reference
and no "assurance" survives. The second prints `9` — all nine numbered rules
ported. The third prints both retargeted pointers.

- [ ] **Step 4: Commit**

```bash
git add instructions/review-dispatch-scope.md
git commit   # subject: Add the reviewer scope dispatch block
git log -1 --pretty=%B | git interpret-trailers --parse
```

Body: name the source (`hube/fin` `docs/prompts/design-review-dispatch.md` at
`5d9534aa`) and the two adaptations — assurance→rigor renaming, and retargeting
the fin-repo-local cross-references to the neighboring
`~/.agents/instructions/` files and the shared always-on file. Then the trailer
block.

---

### Task A3: Port the reader-proxy dispatch block

**Files:**
- Create: `<claude-home-worktree>/instructions/reader-proxy-review-dispatch.md`

**Interfaces:**
- Produces: the path `instructions/reader-proxy-review-dispatch.md`, referenced
  by `review-dispatch-scope.md` (Task A2) and `CLAUDE.md` (Task A4) as
  `~/.agents/instructions/reader-proxy-review-dispatch.md`.

**Source:** `hube/fin` `docs/prompts/reader-proxy-review-dispatch.md` at commit
`5d9534aae16d5ce7f7869ceea3e5109d4c94ca88`. This is a verbatim port — the fin
file carries no repo-local references.

- [ ] **Step 1: Fetch the source and confirm it needs no adaptation**

```bash
gh api repos/hube/fin/contents/docs/prompts/reader-proxy-review-dispatch.md \
  --jq '.content' \
  -f ref=5d9534aae16d5ce7f7869ceea3e5109d4c94ca88 | base64 -d > /tmp/fin-reader-proxy.md
grep -n "assurance\|docs/\|this repository\|fin" /tmp/fin-reader-proxy.md
```

Expected: nothing (exit 1). If the grep prints anything, **stop and report** —
the port is no longer verbatim and the plan's adaptation list is incomplete.

- [ ] **Step 2: Write `instructions/reader-proxy-review-dispatch.md`**

Write this exact content:

````markdown
# Review dispatch: reader proxy

**Canonical source.** A reader-proxy dispatch is this block plus the operator
documentation under review, and nothing else. The block is included
**verbatim**, whether the dispatch is written by hand or assembled by another
agent. Dispatched reviewers inherit nothing; the prompt is the only thing that
binds them.

**To the orchestrator.** Supply the documentation files, their paths, and the
entry point a new operator would start from. Do not supply the design, the
source tree, issue or PR history, or earlier reviews — and do not supply them if
the reviewer asks. The deprivation is the instrument: a reader-proxy handed the
design becomes an ordinary reviewer, and the four categories below are exactly
what a design-holding reviewer is structurally unable to see.

---

You are a new operator. You have the documentation named above and no other
source of truth. Read it in the order it presents itself, and try to follow it.
Report only:

1. **Terms used before they are defined.** A word doing load-bearing work in an
   instruction whose meaning the document has not yet given you.
2. **Steps you cannot complete from the text alone.** The text names an action
   but not the command, the arguments, or the place to run it — or names a
   command the text never establishes exists.
3. **Artifacts named without their producer.** A file, directory, or value you
   are told to have, use, or check, with nothing in the text that creates it.
4. **Instructions whose success condition is not stated.** You can perform the
   step but cannot tell whether it worked.

Nothing else is in scope — not style, not structure, not wording, not ordering,
not completeness against any specification. A finding outside these four
categories is a finding some other review already covers.

**"I cannot complete this step" is a finding, not a blocker.** Do not resolve it
by opening the repository, reading the source, or searching for the answer
elsewhere: finding the answer converts the finding into a non-finding and
destroys the only evidence this review produces. Record the step, what the text
gave you and what it did not, and go on to the next step.

**Refuse context out loud.** If you are offered anything beyond the supplied
documentation, or you find yourself reaching for it, decline in the review and
say what you reached for and at which step — that statement is itself a
category-2 finding. Never proceed silently on information the document did not
give you.

Report each finding as its file and line number, the sentence or step it sits
in, and which of the four categories it falls in. A review with no findings is a
valid review.
````

- [ ] **Step 3: Verify the four reporting categories and the standing rules survived**

```bash
cd <claude-home-worktree>
grep -c "^[0-9]\." instructions/reader-proxy-review-dispatch.md
grep -n "not a blocker\|Refuse context out loud\|do not supply them if" instructions/reader-proxy-review-dispatch.md
```

Expected: `4`, and all three phrases present — the four categories, the
"cannot complete is a finding" rule, the refuse-context-out-loud rule, and the
orchestrator's no-further-context rule.

- [ ] **Step 4: Commit**

```bash
git add instructions/reader-proxy-review-dispatch.md
git commit   # subject: Add the reader-proxy dispatch block
git log -1 --pretty=%B | git interpret-trailers --parse
```

Body: name the source (`hube/fin` at `5d9534aa`) and state that it is a verbatim
port. Then the trailer block.

---

### Task A4: Fold the always-on discipline into `CLAUDE.md`

**Files:**
- Modify: `<claude-home-worktree>/CLAUDE.md`

**Interfaces:**
- Consumes: all three `instructions/` files (Tasks A1–A3), referenced by their
  `~/.agents/instructions/` paths.

This is the always-on half. Keep it **lean** — mechanics belong in
`rigor-levels.md`, not here. Every edit below is an insertion; do not delete or
reword existing text.

- [ ] **Step 1: Confirm the anchors still match**

```bash
cd <claude-home-worktree>
grep -n "^# Best practices$\|^# Mandatory worktree isolation$\|^## Scope of a code review$\|^## Responding to PR Review Feedback$\|^# Working with branches and PRs$" CLAUDE.md
```

Expected: five matches, in that order. If an anchor is missing, **stop and
report** rather than guessing a new insertion point.

- [ ] **Step 2: Insert the shared-instructions pointer**

Insert a new top-level section immediately **before** `# Best practices` (so it
is the first thing every harness reads):

```markdown
# Shared agent instructions

Bulk references shared across harnesses live in `~/.agents/instructions`, a
read-only mount present in every devcontainer. Open these files directly — this
is a plain textual pointer, not an `@import`, because Codex reads `AGENTS.md`
wholesale and would silently ignore an import.

- `~/.agents/instructions/rigor-levels.md` — the rigor-level vocabulary, the
  churn-breaker counting mechanics, ratification triggers, checkpoint cadence,
  thresholds, and the brainstorming elicitation prompts.
- `~/.agents/instructions/review-dispatch-scope.md` — the reviewer scope block,
  included **verbatim** in every design and code review dispatch.
- `~/.agents/instructions/reader-proxy-review-dispatch.md` — the reader-proxy
  dispatch block.

If the directory is absent, the container is missing the consumer mount its
harness Feature warns about at startup; the rules below still bind, but the
referenced detail is unavailable — say so rather than inventing it.
```

- [ ] **Step 3: Insert the design-authoring discipline**

Insert a new top-level section immediately **before**
`# Mandatory worktree isolation` (that is, after the whole `# Best practices`
section):

```markdown
# Design authoring: rigor discipline

- **Rigor levels are owner inputs, not draft properties.** A design that
  specifies a dimension with owner-chosen rigor — durability, performance
  budgets, security posture, compatibility guarantees, test rigor — declares its
  **Rigor levels** in a section grouped with its scope statements (directly
  after Non-goals, in documents using that convention). A weak level **caps**
  machinery; a strong level **authorizes** it. Absent any stated level the
  default is the weakest: primary data must never be damaged or lost, everything
  else is presumed re-doable. Full vocabulary, status markers, named ladders,
  and table format: `~/.agents/instructions/rigor-levels.md`.
- **Altitude step — required before any fix that adds state.** Before
  implementing a finding whose fix would add a state machine, protocol,
  invariant, or durability mechanism, answer two questions in order:
  1. Can the finding be closed by **deleting the claim or promise it
     contradicts** instead of strengthening the mechanism? Prefer subtraction: a
     deleted claim cannot be contested next round, whereas each added mechanism
     is fresh surface a later round can find fault with.
  2. Does the requirement the finding protects trace to a **Decided** rigor
     level or stated goal? If not, do not fix — route it to the owner as a
     requirement question. An author-invented invariant is not a requirement.
- **Defer implementation-level correctness to implementation.** Anything whose
  truth is established by running code — I/O ordering, concurrency windows,
  exact library or platform semantics — is resolved against real code with a
  required fixture, not in prose. A design specifies **what it guarantees**; it
  specifies mechanism only where the guarantee itself demands one. "Defer to
  implementation with a required fixture" is a legitimate disposition for such a
  finding, unless the stated guarantee is itself unmeetable.
- **Elicit levels before designing mechanisms.** When brainstorming a feature
  that touches a dimension with owner-chosen rigor, ask about the owner's
  tolerance — what outcome must hold, what may be lost or degraded, who consumes
  the evidence, how often the scenario arises — before proposing machinery, and
  record the answers as `provisional (author-proposed)` levels. The
  per-dimension prompts are in `~/.agents/instructions/rigor-levels.md`.
```

- [ ] **Step 4: Extend `## Scope of a code review`**

Insert these three bullets at the **top** of the bullet list in
`## Scope of a code review`, before the existing "Review the work and the claims
it makes" bullet:

```markdown
- **Meets, not exceeds.** Verify the work MEETS each Decided rigor level. A
  finding that it fails to EXCEED a Decided level is out of scope as a defect.
  If the gap looks unintended, raise a **one-line calibration question to the
  owner** — no severity label, no prescribed fix. A prescription presupposes the
  answer (that the level should rise), and a severity label puts the question in
  the findings queue, creating closure pressure to add mechanism before the
  owner has decided.
- **Over-engineering is a defect.** A mechanism defending a scenario the Decided
  levels or Non-goals exclude is a valid Important finding — recommend
  **deletion**, not refinement. Finding removable machinery earns equal credit
  with finding missing machinery.
- **Don't infer scope or reverse a decision.** When it is unclear whether a
  Decided level applies to the mechanism under review, or when a deletion
  finding would reverse a *different* settled decision, ask a calibration or
  decision-conflict question and leave the mechanism in place until the owner
  reconciles. Inferring applicability is how machinery gets approved that no
  level authorized; deleting on inference is how a settled decision gets
  silently reversed.
```

Then append this bullet at the **end** of the same list, after the existing
"Encode these scope rules in every reviewer dispatch prompt" bullet:

```markdown
- **The canonical reviewer scope block is
  `~/.agents/instructions/review-dispatch-scope.md`.** Include it **verbatim**
  in every design and code review dispatch, after the list of settled decisions
  — code reviews measure the implementation against the governing design's
  Decided levels. Never include it in a reader-proxy dispatch, which carries no
  context beyond its own prompt and the documentation under review.
```

- [ ] **Step 5: Add the breaker as the matched complement in `## Responding to PR Review Feedback`**

Insert immediately **after** the existing "If the same decision is contested
across more than one review round" bullet:

```markdown
- **If three consecutive review rounds produce findings confined to the same
  section or mechanism, stop fixing that mechanism** and record an options memo
  for the owner: *finish the machinery / simplify to a weaker stated level /
  accept the risk explicitly*. This is the matched complement to the rule above:
  that one catches disagreement-churn, this one catches uncontested accretion,
  where each round agrees with the last and adds. The thresholds differ
  deliberately — disagreement is the sharper signal, so a contested decision
  escalates after two rounds while accretion is allowed three. The breaker fires
  on repetition on the same ground, not on breadth: a deliberate multi-angle
  review sweeping many mechanisms once is not churn. It routes **unresolved
  requirement questions** to the owner and is **not** a way to decline an
  instruction the owner has already given — a finding that arrives with the
  owner's decision attached is fixed, not escalated. Counting mechanics, and
  what stays unblocked while a mechanism is blocked, are in
  `~/.agents/instructions/rigor-levels.md`.
- **Reply in the register the finding deserves, not the one it arrived in.** An
  inflated minor finding is answered briefly and corrected; matching its
  apparatus doubles the cost of an error already agreed on.
- **Concede separately from contesting.** Post the concession by itself, with
  nothing attached. A rebuttal, if it survives the test below, is a separate
  message — a concession sharing a message with a rebuttal reads as a preamble
  to it and invites another round, whether or not it has a heading of its own.
- **Ask what a reply changes before writing it.** A reply is commentary, however
  correct, unless it changes a named artifact or is itself the one-line proposal
  of a guard. This governs how much a reply elaborates, not whether it is given
  — every finding still receives an explicit accept or decline.
```

- [ ] **Step 6: Add the change-sequencing guardrails to `# Working with branches and PRs`**

Append these three bullets to the end of the bullet list directly under
`# Working with branches and PRs` (after "When considering conflicting feedback
on a PR…"):

```markdown
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
  command; it can only describe the workaround. That check is not conformance
  evidence, so it does not trigger the separation rule above.
- **Dispatch a reader-proxy review on any PR that authors or revises
  operator-facing prose**, using
  `~/.agents/instructions/reader-proxy-review-dispatch.md` verbatim. A PR that
  only repairs a reference — a renamed path, a deleted link — does not trigger
  it: there is no new prose for a new reader to fail on, and firing the review
  there teaches everyone to treat the rule as noise.
```

- [ ] **Step 7: Verify the file is still coherent**

```bash
cd <claude-home-worktree>
grep -c "~/.agents/instructions" CLAUDE.md
grep -n "@~/.agents\|@instructions" CLAUDE.md
git diff --stat CLAUDE.md
```

Expected: the first count is **8 or more** (pointer section lists three files;
the design-authoring, scope, feedback, and sequencing sections each cite at
least one). The second prints nothing — no `@import` form was used. The diff
shows **only insertions** (`git diff CLAUDE.md | grep -c '^-[^-]'` must be `0`).

- [ ] **Step 8: Commit**

```bash
git add CLAUDE.md
git commit   # subject: Add always-on rigor and anti-ratchet review discipline
git log -1 --pretty=%B | git interpret-trailers --parse
```

Body: list the sections gaining rules and note the pointer is plain text, not an
`@import`, because Codex reads `AGENTS.md` wholesale. Then the trailer block.

---

### Task A5: Reader-proxy review and the claude-home PR

**Files:** none edited.

The design's own change-sequencing rule applies to this PR: it authors
operator-facing prose, so it triggers a reader-proxy review.

- [ ] **Step 1: Dispatch the reader-proxy review**

Dispatch one subagent whose entire prompt is the content of
`instructions/reader-proxy-review-dispatch.md` (as written in Task A3), followed
by the paths of the three new `instructions/` files and the entry point a new
operator would start from (`instructions/rigor-levels.md`). Supply **nothing
else** — no design, no source tree, no PR history — and refuse further context
if the reviewer asks for it.

- [ ] **Step 2: Triage the findings**

For each finding, decide accept or decline explicitly. Accepted findings are
fixed in place and committed; declined findings get a one-line reason. Do not
add mechanism to close a category-1 or category-3 finding that a definition or a
sentence would close.

- [ ] **Step 3: Push and open the PR**

```bash
cd <claude-home-worktree>
git push -u origin implement/rigor-levels-instructions
gh pr create --repo hube/claude-home --base main \
  --title "Add rigor levels and anti-ratchet review discipline" \
  --body-file <(cat)   # body below
gh pr edit --repo hube/claude-home <N> --add-reviewer hube
```

PR body states: what lands (the three `instructions/` files, the `.gitignore`
allow-list, the `CLAUDE.md` inline discipline); that it implements
`hube/devcontainer` design `2026-07-22-rigor-levels-anti-ratchet-design.md`
merged in `hube/devcontainer#55`; that the two ported blocks come from
`hube/fin` at `5d9534aa` with the adaptations named in Task A2; and that
`hube/devcontainer` plumbing follows in a separate PR gated on the host deploy.
End with the metadata trailer block in a fenced code block.

- [ ] **Step 4: Monitor checks**

```bash
gh pr checks --repo hube/claude-home <N> --watch
```

Fix anything that fails until all checks pass. Report the result plainly.

---

## Phase G — Host deployment gate (owner action)

**This is not an implementation task. It cannot be done from inside the
container** — `~/.claude/instructions` is a path on the *host*, and the
container sees only the specific bind mounts the Feature declares
(`~/.claude/CLAUDE.md` and `~/.claude/projects`), not the host's `~/.claude`
directory itself.

The gate is **host state, not repository merge order**: Docker rejects a bind
mount whose host source does not exist, breaking container startup outright
before any postStart warning could run. Merging Phase A to `main` creates
nothing on the host until it is deployed into the checkout backing `~/.claude`.

- [ ] **Step 1: Owner deploys Phase A to the host**

After the claude-home PR merges, the owner updates the host's `~/.claude` from
claude-home `main` so that `~/.claude/instructions/` exists there with all three
files.

- [ ] **Step 2: Owner confirms the host directory exists**

On the **host** (not in the container):

```bash
ls -1 ~/.claude/instructions
```

Expected: exactly three files — `reader-proxy-review-dispatch.md`,
`rigor-levels.md`, and `review-dispatch-scope.md`.

- [ ] **Step 3: Report the gate state before merging Phase B**

Phase B's PR may be **opened** before this gate clears — its Feature and test
changes are inert without the mount — but it must **not merge** until the owner
confirms Step 2. State the gate explicitly in the Phase B PR body.

---

## Phase B — `hube/devcontainer` (plumbing)

All Phase B work happens in the existing worktree
`/workspaces/agent-devcontainer/devcontainer/.claude/worktrees/calm-napping-turtle`
on branch `worktree-calm-napping-turtle`, already fast-forwarded to `029d6f8`.

### Task B0: Repair the malformed Claude Feature manifest

**Files:**
- Modify: `.devcontainer/local-features/claude/devcontainer-feature.json`

This is a **pre-existing defect on `main`**, not part of the design. It gets its
own commit because Task B1 must edit the same file and cannot do so on top of
invalid JSON. The three `.claude-1/2/3` mount objects added in `3f527ba` are
missing the commas that separate them from the preceding object.

- [ ] **Step 1: Write the failing check**

```bash
cd /workspaces/agent-devcontainer/devcontainer/.claude/worktrees/calm-napping-turtle
python3 -c "
import json, re, sys
raw = open('.devcontainer/local-features/claude/devcontainer-feature.json').read()
json.loads(re.sub(r'(?m)^\s*//.*$', '', raw))
print('VALID')
"
```

Expected: **not** `VALID` — the command exits non-zero with
`json.decoder.JSONDecodeError: Expecting ',' delimiter: line 27 column 5`.

- [ ] **Step 2: Add the three missing commas**

In `.devcontainer/local-features/claude/devcontainer-feature.json`, the closing
brace of the mount object immediately preceding each of these comment lines
must become `},`:

- `// Claude Code configuration 1`
- `// Claude Code configuration 2`
- `// Claude Code configuration 3`

That is, each occurrence of

```json
      "target": "/home/${localEnv:USERNAME:devcontainer}/.claude/CLAUDE.md"
    }
    // Claude Code configuration 1
```

becomes

```json
      "target": "/home/${localEnv:USERNAME:devcontainer}/.claude/CLAUDE.md"
    },
    // Claude Code configuration 1
```

and likewise for the `.claude-1/CLAUDE.md` and `.claude-2/CLAUDE.md` targets
preceding comments 2 and 3. Change nothing else.

- [ ] **Step 3: Re-run the check**

```bash
python3 -c "
import json, re
raw = open('.devcontainer/local-features/claude/devcontainer-feature.json').read()
m = json.loads(re.sub(r'(?m)^\s*//.*\$', '', raw))
print('VALID,', len(m['mounts']), 'mounts')
"
```

Expected: `VALID, 12 mounts`.

- [ ] **Step 4: Commit**

```bash
git add .devcontainer/local-features/claude/devcontainer-feature.json
git commit   # subject: Fix malformed JSON in the Claude Feature manifest
git log -1 --pretty=%B | git interpret-trailers --parse
```

Body: state the problem (three mount objects added in `3f527ba` lack separating
commas, so the manifest is not valid JSON), the consequence (any consumer or
test that parses it with a strict JSON parser fails), and that the fix adds only
the commas. Then the trailer block.

---

### Task B1: Claude Feature — postStart warning, docs, tests

**Files:**
- Create: `.devcontainer/local-features/claude/bin/devcontainer-feature/claude/postStartScript.sh`
- Create: `.devcontainer/local-features/claude/test/test-poststart.sh`
- Create: `.devcontainer/local-features/claude/NOTES.md`
- Modify: `.devcontainer/local-features/claude/devcontainer-feature.json`
- Modify: `.devcontainer/local-features/claude/install.sh`
- Modify: `README.md`

**Interfaces:**
- Produces: the container target path `~/.agents/instructions`, referenced
  identically by Task B2's Codex hook and Task B3's consumer mount.
- Produces: the hook path
  `~/bin/devcontainer-feature/claude/postStartScript.sh`, the value the manifest
  `postStartCommand` must hold.

- [ ] **Step 1: Write the failing test**

Create `.devcontainer/local-features/claude/test/test-poststart.sh` with this
content:

```bash
#!/usr/bin/env bash
# Tests the shared-instructions mount warning. The hook must never fail
# container start, and must distinguish "absent" from "present but not a
# directory" — the two need different remedies.
set -uo pipefail

HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/bin/devcontainer-feature/claude/postStartScript.sh"
passed=0
failed=0

pass() { printf 'ok   %s\n' "$1"; passed=$((passed + 1)); }
fail() { printf 'FAIL %s\n     %s\n' "$1" "$2"; failed=$((failed + 1)); }

setup_world() {
  WORLD="$(mktemp -d)"
  export HOME="$WORLD/home"
  mkdir -p "$HOME"
}

teardown_world() { rm -rf "$WORLD"; }

run_hook() {
  out="$("$HOOK" 2>&1)"
  rc=$?
}

# A present directory is the healthy case: exit 0, say nothing.
setup_world
mkdir -p "$HOME/.agents/instructions"
run_hook
[[ $rc -eq 0 ]] && pass "mounted: exits 0" || fail "mounted: exits 0" "got $rc"
[[ -z "$out" ]] && pass "mounted: stays silent" || fail "mounted: stays silent" "$out"
teardown_world

# An absent directory warns without blocking container start.
setup_world
run_hook
[[ $rc -eq 0 ]] && pass "absent: exits 0" || fail "absent: exits 0" "got $rc"
[[ "$out" == *"claude: $HOME/.agents/instructions is absent, so the shared agent instructions are not mounted."* ]] && pass "absent: states problem" || fail "absent: states problem" "$out"
[[ "$out" == *"Claude Code cannot resolve the ~/.agents/instructions pointer in CLAUDE.md, so the rigor-levels reference and the reviewer dispatch blocks are unavailable."* ]] && pass "absent: states consequence" || fail "absent: states consequence" "$out"
[[ "$out" == *"Add the consumer mount documented in .devcontainer/local-features/claude/NOTES.md to devcontainer.json, ensure ~/.claude/instructions exists on the host, then restart the container."* ]] && pass "absent: states remedy" || fail "absent: states remedy" "$out"
teardown_world

# A non-directory at the target needs a different remedy than an absent one.
setup_world
mkdir -p "$HOME/.agents"
: > "$HOME/.agents/instructions"
run_hook
[[ $rc -eq 0 ]] && pass "not a directory: exits 0" || fail "not a directory: exits 0" "got $rc"
[[ "$out" == *"claude: $HOME/.agents/instructions exists but is not a directory, so the shared agent instructions cannot be read."* ]] && pass "not a directory: states problem" || fail "not a directory: states problem" "$out"
[[ "$out" == *"Remove it, declare the consumer mount documented in .devcontainer/local-features/claude/NOTES.md, then restart the container."* ]] && pass "not a directory: states remedy" || fail "not a directory: states remedy" "$out"
[[ "$out" != *"is absent"* ]] && pass "not a directory: does not report absence" || fail "not a directory: does not report absence" "$out"
teardown_world

# The manifest must actually run the hook, or none of the above ever executes.
manifest_command="$(python3 -c "
import json, re, sys
raw = open('$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/devcontainer-feature.json').read()
print(json.loads(re.sub(r'(?m)^\s*//.*$', '', raw)).get('postStartCommand', ''))
")"
[[ "$manifest_command" == "~/bin/devcontainer-feature/claude/postStartScript.sh" ]] && pass "manifest: declares postStartCommand" || fail "manifest: declares postStartCommand" "got '$manifest_command'"

# install.sh must copy bin/ executable, or the declared hook is never installed.
install_sh="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/install.sh"
grep -q 'F755' "$install_sh" && grep -q '"bin/\."' "$install_sh" && pass "install: copies bin executable" || fail "install: copies bin executable" "install.sh does not rsync bin/. with F755"

printf '\n%d passed, %d failed\n' "$passed" "$failed"
[[ $failed -eq 0 ]]
```

Then make it executable: `chmod +x .devcontainer/local-features/claude/test/test-poststart.sh`

- [ ] **Step 2: Run the test to verify it fails**

Run: `.devcontainer/local-features/claude/test/test-poststart.sh`
Expected: FAIL — the hook file does not exist, so every `run_hook` case fails,
and the manifest and install assertions fail too.

- [ ] **Step 3: Write the hook**

Create
`.devcontainer/local-features/claude/bin/devcontainer-feature/claude/postStartScript.sh`:

```bash
#!/usr/bin/env bash
# Warns when the shared agent instructions mount is absent. Never fails
# container start: missing shared instructions degrade guidance, they do not
# make the container unusable.
set -uo pipefail

instructions="$HOME/.agents/instructions"

if [[ -d "$instructions" ]]; then
  exit 0
fi

# A file or symlink at the target is a different failure from nothing at all:
# it must be removed before a bind mount can land there.
if [[ -e "$instructions" || -L "$instructions" ]]; then
  printf '%s\n' \
    "claude: $instructions exists but is not a directory, so the shared agent instructions cannot be read. Claude Code cannot resolve the ~/.agents/instructions pointer in CLAUDE.md, so the rigor-levels reference and the reviewer dispatch blocks are unavailable. Remove it, declare the consumer mount documented in .devcontainer/local-features/claude/NOTES.md, then restart the container." >&2
  exit 0
fi

printf '%s\n' \
  "claude: $instructions is absent, so the shared agent instructions are not mounted. Claude Code cannot resolve the ~/.agents/instructions pointer in CLAUDE.md, so the rigor-levels reference and the reviewer dispatch blocks are unavailable. Add the consumer mount documented in .devcontainer/local-features/claude/NOTES.md to devcontainer.json, ensure ~/.claude/instructions exists on the host, then restart the container." >&2

exit 0
```

Then: `chmod +x .devcontainer/local-features/claude/bin/devcontainer-feature/claude/postStartScript.sh`

- [ ] **Step 4: Declare `postStartCommand` in the manifest**

In `.devcontainer/local-features/claude/devcontainer-feature.json`, add this
key after the closing `]` of `mounts`:

```json
  "postStartCommand": "~/bin/devcontainer-feature/claude/postStartScript.sh"
```

Remember the comma after the `mounts` array's `]`.

- [ ] **Step 5: Install the hook from `install.sh`**

In `.devcontainer/local-features/claude/install.sh`, inside the root branch,
immediately after the existing `rsync ... "home/." "/home/${_CONTAINER_USER}"`
block and **before** the `for i in {1..3}` loop, add:

```bash
  # Separate rsync: hooks need the execute bit, which the config copy's F644
  # would strip.
  rsync -rp \
      --chown=${_CONTAINER_USER}:${_CONTAINER_USER} \
      --chmod=D755,F755 \
      "bin/." "/home/${_CONTAINER_USER}/bin"
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `.devcontainer/local-features/claude/test/test-poststart.sh`
Expected: PASS — `11 passed, 0 failed`.

- [ ] **Step 7: Write `NOTES.md`**

Create `.devcontainer/local-features/claude/NOTES.md`:

````markdown
# Claude

This local feature installs Claude Code and configures up to four independent
Claude Code accounts (`~/.claude` and `~/.claude-1` through `~/.claude-3`), each
backed by its own named volume, and each sharing the host's `CLAUDE.md` and
`projects` directory.

## Shared agent instructions

Bulk agent instructions shared across every harness in the container — the
rigor-levels reference and the verbatim reviewer dispatch blocks — are read from
`~/.agents/instructions`. The shared `CLAUDE.md` points at that path as plain
text.

This Feature owns only the container **target** path. The mount itself is
**consumer-declared**: its host source `~/.claude/instructions` is specific to
the Claude configuration layout, and hardcoding it in a Feature would leak that
layout into otherwise neutral Feature source and give the single target
duplicate owners. Add it once to your `devcontainer.json`, not per Feature and
not per account:

```json
{
  "mounts": [
    {
      "type": "bind,readonly",
      "source": "${localEnv:HOME}/.claude/instructions",
      "target": "/home/${localEnv:USERNAME:devcontainer}/.agents/instructions"
    }
  ]
}
```

One mount serves every harness in the container: the Codex feature reads the
same target path. The mount is read-only because the instructions are read,
never written, so no approved command in any harness can alter them through it.

**The host directory must exist before you declare the mount.** Docker rejects a
bind mount whose host source is missing, and that failure breaks container
startup outright — before any startup warning could run. Create or deploy
`~/.claude/instructions` on the host first, then add the mount.

If the mount is absent, the container still starts. The Feature's startup hook
warns on stderr, Claude Code loads its always-on `CLAUDE.md` normally, and only
the referenced bulk detail is unavailable.
````

- [ ] **Step 8: Link the notes from `README.md`**

In the "The devcontainer in this repo includes:" list in `README.md`, replace
the plain `* Claude Code` item with:

```markdown
* Claude Code; the shared agent instructions mount it expects is described in
  the [Claude feature notes](.devcontainer/local-features/claude/NOTES.md).
```

- [ ] **Step 9: Confirm the Codex documentation test still passes**

`README.md` is asserted on by the Codex feature's documentation test. Run it:

Run: `.devcontainer/local-features/codex/test/test-documentation.sh`
Expected: PASS. If it fails on the README image-contents list shape, the new
item must match the same `* …` / two-space-continuation form the Codex item
uses — fix the item, not the test.

- [ ] **Step 10: Commit**

```bash
git add .devcontainer/local-features/claude/ README.md
git commit   # subject: Warn when the shared agent instructions mount is absent
git log -1 --pretty=%B | git interpret-trailers --parse
```

Body: the Feature owns only the container target; the mount is
consumer-declared; the hook exits 0 on every path so a missing mount never
blocks container start. Then the trailer block.

---

### Task B2: Codex Feature — postStart warning, docs, tests

**Files:**
- Create: `.devcontainer/local-features/codex/bin/devcontainer-feature/codex/postStartScript.sh`
- Create: `.devcontainer/local-features/codex/test/test-poststart.sh`
- Modify: `.devcontainer/local-features/codex/devcontainer-feature.json`
- Modify: `.devcontainer/local-features/codex/test/test-feature-config.py`
- Modify: `.devcontainer/local-features/codex/NOTES.md`

**Interfaces:**
- Consumes: the container target `~/.agents/instructions` established in Task B1.
- Produces: the hook path `~/bin/devcontainer-feature/codex/postStartScript.sh`.

Codex's `install.sh` already rsyncs `bin/.` with `--chmod=D755,F755`, so no
installer change is needed here.

- [ ] **Step 1: Write the failing test**

Create `.devcontainer/local-features/codex/test/test-poststart.sh` with the same
structure as Task B1's test, with these substitutions: `HOOK` resolves to
`bin/devcontainer-feature/codex/postStartScript.sh`; every expected message
begins `codex:` instead of `claude:`; the consequence sentence is
`Codex cannot resolve the ~/.agents/instructions pointer in AGENTS.md, so the rigor-levels reference and the reviewer dispatch blocks are unavailable.`;
the remedy sentences name
`.devcontainer/local-features/codex/NOTES.md`; and the final `install.sh`
assertion is dropped (Codex's installer already copies `bin/`). Keep the
manifest assertion, changed to expect
`~/bin/devcontainer-feature/codex/postStartScript.sh`.

Write it out in full — do not `source` or import Task B1's file; the two
Features are independent units and a shared helper would couple them.

Then: `chmod +x .devcontainer/local-features/codex/test/test-poststart.sh`

- [ ] **Step 2: Run the test to verify it fails**

Run: `.devcontainer/local-features/codex/test/test-poststart.sh`
Expected: FAIL — the hook does not exist and the manifest declares no
`postStartCommand`.

- [ ] **Step 3: Write the hook**

Create
`.devcontainer/local-features/codex/bin/devcontainer-feature/codex/postStartScript.sh`:

```bash
#!/usr/bin/env bash
# Warns when the shared agent instructions mount is absent. Never fails
# container start: missing shared instructions degrade guidance, they do not
# make the container unusable.
set -uo pipefail

instructions="$HOME/.agents/instructions"

if [[ -d "$instructions" ]]; then
  exit 0
fi

# A file or symlink at the target is a different failure from nothing at all:
# it must be removed before a bind mount can land there.
if [[ -e "$instructions" || -L "$instructions" ]]; then
  printf '%s\n' \
    "codex: $instructions exists but is not a directory, so the shared agent instructions cannot be read. Codex cannot resolve the ~/.agents/instructions pointer in AGENTS.md, so the rigor-levels reference and the reviewer dispatch blocks are unavailable. Remove it, declare the consumer mount documented in .devcontainer/local-features/codex/NOTES.md, then restart the container." >&2
  exit 0
fi

printf '%s\n' \
  "codex: $instructions is absent, so the shared agent instructions are not mounted. Codex cannot resolve the ~/.agents/instructions pointer in AGENTS.md, so the rigor-levels reference and the reviewer dispatch blocks are unavailable. Add the consumer mount documented in .devcontainer/local-features/codex/NOTES.md to devcontainer.json, ensure ~/.claude/instructions exists on the host, then restart the container." >&2

exit 0
```

Then: `chmod +x .devcontainer/local-features/codex/bin/devcontainer-feature/codex/postStartScript.sh`

- [ ] **Step 4: Declare `postStartCommand` in the manifest**

In `.devcontainer/local-features/codex/devcontainer-feature.json`, add after the
existing `postCreateCommand` line:

```json
  "postStartCommand": "~/bin/devcontainer-feature/codex/postStartScript.sh",
```

Keep valid JSON — this manifest has no comments and is parsed with a strict
`json.loads` by three existing tests.

- [ ] **Step 5: Assert the new key in the existing config test**

In `.devcontainer/local-features/codex/test/test-feature-config.py`, beside the
existing `POST_CREATE_COMMAND` constant (line ~24), add:

```python
POST_START_COMMAND = "~/bin/devcontainer-feature/codex/postStartScript.sh"
```

and in the check list beside the existing `postCreateCommand` entry (line ~430),
add:

```python
        (
            "postStartCommand",
            lambda: assert_equal(manifest.get("postStartCommand"), POST_START_COMMAND),
        ),
```

- [ ] **Step 6: Run the tests to verify they pass**

```bash
.devcontainer/local-features/codex/test/test-poststart.sh
python3 .devcontainer/local-features/codex/test/test-feature-config.py
```

Expected: both PASS.

- [ ] **Step 7: Document the mount in the Codex notes**

In `.devcontainer/local-features/codex/NOTES.md`, insert a new
`## Shared agent instructions` section immediately before
`## Creation and health failures`:

````markdown
## Shared agent instructions

Codex reads its always-on guidance from `~/.codex/AGENTS.md`, which this Feature
mounts from the host's shared agent instruction file. Bulk references that file
points at — the rigor-levels reference and the verbatim reviewer dispatch blocks
— are read from `~/.agents/instructions`. The pointer is plain text, not an
`@path` import: Codex reads `AGENTS.md` wholesale and does not expand imports,
so an import would silently do nothing.

This Feature owns only the container **target** path. The mount is
**consumer-declared** — its host source is specific to the Claude configuration
layout — and is declared **once** for the whole container, serving every harness
in it. The declaration and its host prerequisite are documented in the
[Claude feature notes](../claude/NOTES.md).

If the mount is absent the container still starts. The Feature's startup hook
warns on stderr, Codex loads `AGENTS.md` normally, and only the referenced bulk
detail is unavailable.
````

- [ ] **Step 8: Run the Codex documentation test**

Run: `.devcontainer/local-features/codex/test/test-documentation.sh`
Expected: PASS. The test asserts required NOTES content and forbids
maintainer-only procedures; the new section adds neither a forbidden string nor
removes a required one.

- [ ] **Step 9: Commit**

```bash
git add .devcontainer/local-features/codex/
git commit   # subject: Warn from Codex when the instructions mount is absent
git log -1 --pretty=%B | git interpret-trailers --parse
```

Body: same reasoning as B1, plus the note that no installer change is needed
because Codex's `install.sh` already copies `bin/` with the execute bit. Then
the trailer block.

---

### Task B3: Declare the consumer mount

**Files:**
- Modify: `.devcontainer/devcontainer.json`
- Create: `.devcontainer/local-features/claude/test/test-consumer-mount.sh`

**Interfaces:**
- Consumes: the container target `~/.agents/instructions` from Tasks B1 and B2.

The design scopes verification here precisely: **verify the configuration we
own** — that the consumer `devcontainer.json` declares the mount with the
correct source, target, and read-only flag — and **assume Docker enforces a
correctly declared read-only bind** rather than re-testing that enforcement
(Decided, owner, 2026-07-26:
https://github.com/hube/devcontainer/pull/55#discussion_r3651595630). Do not
write a runtime test that mounts something and tries to write to it.

- [ ] **Step 1: Write the failing test**

Create `.devcontainer/local-features/claude/test/test-consumer-mount.sh`:

```bash
#!/usr/bin/env bash
# Verifies the configuration this repo owns: that its own consumer
# devcontainer.json declares the shared-instructions mount with the source,
# target, and read-only flag the Features' target path depends on. Docker's
# enforcement of a correctly declared read-only bind is assumed, not retested.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
CONSUMER="$ROOT/.devcontainer/devcontainer.json"

python3 - "$CONSUMER" <<'PY'
import json, re, sys
from pathlib import Path

raw = Path(sys.argv[1]).read_text(encoding="utf-8")
config = json.loads(re.sub(r"(?m)^\s*//.*$", "", raw))

EXPECTED_SOURCE = "${localEnv:HOME}/.claude/instructions"
EXPECTED_TARGET = "/home/${localEnv:USERNAME:devcontainer}/.agents/instructions"

failures = []
mounts = config.get("mounts", [])
matching = [m for m in mounts if isinstance(m, dict) and m.get("target") == EXPECTED_TARGET]

if not matching:
    failures.append(
        f"consumer devcontainer.json declares no mount targeting {EXPECTED_TARGET}"
    )
elif len(matching) > 1:
    failures.append(
        f"consumer devcontainer.json declares {len(matching)} mounts targeting "
        f"{EXPECTED_TARGET}; the mount is declared once for the whole container"
    )
else:
    mount = matching[0]
    if mount.get("source") != EXPECTED_SOURCE:
        failures.append(
            f"instructions mount source is {mount.get('source')!r}, expected {EXPECTED_SOURCE!r}"
        )
    if "readonly" not in str(mount.get("type", "")):
        failures.append(
            f"instructions mount type is {mount.get('type')!r}, which is not read-only"
        )

if failures:
    print("FAIL")
    for failure in failures:
        print(f"  {failure}")
    raise SystemExit(1)

print("ok   consumer devcontainer.json declares the read-only instructions mount")
PY
```

Then: `chmod +x .devcontainer/local-features/claude/test/test-consumer-mount.sh`

- [ ] **Step 2: Run the test to verify it fails**

Run: `.devcontainer/local-features/claude/test/test-consumer-mount.sh`
Expected: FAIL with
`consumer devcontainer.json declares no mount targeting /home/${localEnv:USERNAME:devcontainer}/.agents/instructions`.

- [ ] **Step 3: Declare the mount**

In `.devcontainer/devcontainer.json`, add a top-level `mounts` array after the
`features` block:

```json
  "mounts": [
    // Bulk agent instructions shared by every harness in the container.
    // Consumer-declared: the source is specific to the Claude configuration
    // layout, so a Feature must not hardcode it. Read-only: the instructions
    // are read, never written.
    {
      "type": "bind,readonly",
      "source": "${localEnv:HOME}/.claude/instructions",
      "target": "/home/${localEnv:USERNAME:devcontainer}/.agents/instructions"
    }
  ],
```

`"type": "bind,readonly"` is this repo's established read-only bind form — see
`local-features/ssh`, which mounts `known_hosts` the same way.

- [ ] **Step 4: Run the test to verify it passes**

Run: `.devcontainer/local-features/claude/test/test-consumer-mount.sh`
Expected: `ok   consumer devcontainer.json declares the read-only instructions mount`.

- [ ] **Step 5: Commit**

```bash
git add .devcontainer/devcontainer.json .devcontainer/local-features/claude/test/test-consumer-mount.sh
git commit   # subject: Declare the shared agent instructions consumer mount
git log -1 --pretty=%B | git interpret-trailers --parse
```

Body: one mount serves every harness; declared by the consumer because the
source is Claude-layout-specific; read-only; the host directory must exist
before a container using this config starts. Then the trailer block.

---

### Task B4: Full test sweep, reader-proxy review, and the devcontainer PR

**Files:** none edited unless a check fails.

- [ ] **Step 1: Run every Feature test in the repo**

```bash
cd /workspaces/agent-devcontainer/devcontainer/.claude/worktrees/calm-napping-turtle
for t in .devcontainer/local-features/*/test/*.sh; do
  printf '\n=== %s ===\n' "$t"
  "$t" || printf 'FAILED: %s\n' "$t"
done
for t in .devcontainer/local-features/*/test/*.py; do
  printf '\n=== %s ===\n' "$t"
  python3 "$t" || printf 'FAILED: %s\n' "$t"
done
```

Expected: no `FAILED:` lines. Some Codex tests require a running Docker daemon
or a built image; if one skips or fails for a reason that predates this branch,
verify that by running the same test on `origin/main` in a scratch checkout and
report the comparison — do not assert it is pre-existing without checking.

- [ ] **Step 2: Verify both manifests still parse**

```bash
python3 -c "
import json, re
from pathlib import Path
for p in Path('.devcontainer/local-features').glob('*/devcontainer-feature.json'):
    json.loads(re.sub(r'(?m)^\s*//.*\$', '', p.read_text()))
    print('ok', p)
"
```

Expected: one `ok` line per Feature, no exception.

- [ ] **Step 3: Dispatch the reader-proxy review**

This PR authors operator-facing prose (`claude/NOTES.md`, the new Codex NOTES
section, the README item), so the design's change-sequencing guardrail applies.
Dispatch one subagent whose entire prompt is the reader-proxy block written in
Task A3, plus the paths of `.devcontainer/local-features/claude/NOTES.md`, the
Codex NOTES section, and the README item, naming the README as the entry point.
Supply nothing else, and refuse further context if asked.

- [ ] **Step 4: Triage the findings**

Accept or decline each explicitly. A category-3 finding ("artifact named without
its producer") on the host `~/.claude/instructions` directory is expected and
should be closed by a sentence in `NOTES.md`, not by adding a Feature that
creates the directory — the design places the host directory outside this
repo's ownership.

- [ ] **Step 5: Push and open the PR**

```bash
git push -u origin worktree-calm-napping-turtle
gh pr create --repo hube/devcontainer --base main \
  --title "Mount the shared agent instructions directory" \
  --body-file <(cat)
gh pr edit --repo hube/devcontainer <N> --add-reviewer hube
```

PR body states: what lands (consumer mount, two postStart warnings, tests, the
Feature notes, the pre-existing manifest JSON repair); that it implements the
`hube/devcontainer#55` design; **the merge gate** — this PR must not merge until
`~/.claude/instructions` exists on the host, because Docker rejects a bind mount
whose source is missing and that breaks container startup before any warning can
run; and the link to the claude-home PR it depends on. End with the metadata
trailer block in a fenced code block.

- [ ] **Step 6: Monitor checks**

```bash
gh pr checks --repo hube/devcontainer <N> --watch
```

The repo's only workflow publishes on push to `main`, so a PR may report no
checks. If that is the case, say so plainly rather than claiming checks passed.

- [ ] **Step 7: Report worktree state**

Report, for both repositories: path, branch, ownership mechanism and identifier,
task status, and whether changes are uncommitted, committed, or pushed.

---

## Self-Review

**Spec coverage** — every design section maps to a task:

| Design section | Task |
|---|---|
| Rigor levels (vocabulary, status markers, default floor, ladders, format) | A1 |
| Altitude step | A4 (inline) |
| Review scope: meets, not exceeds | A4 (inline), A2 (dispatch block) |
| Churn tripwire: two matched halves | A4 (inline), A1 (mechanics) |
| Defer implementation-level correctness | A4 (inline), A2 (rule 5) |
| Review exchanges: proportionality | A4 (inline), A2 (rules 7–9) |
| Change sequencing | A4 (inline) |
| The reader-proxy dispatch | A3; exercised in A5 and B4 |
| Ratification triggers | A1 |
| Owner checkpoint cadence | A1 |
| Brainstorming: elicit levels first | A1 (prompts), A4 (inline trigger) |
| Thresholds | A1 |
| Hybrid placement: inline + directory-mounted reference | A4 + A1–A3 |
| The mount (consumer-declared, once, read-only) | B3 |
| Feature target + postStart absent-mount warning | B1, B2 |
| Feature `NOTES.md` documents the consumer mount | B1, B2 |
| claude-home `.gitignore` allow-list | A1 |
| Rollout ordering (host-state gate) | G |
| Open question: deployed `CLAUDE.md` parity | A0 Step 4 |

**Not implemented, by design:** mechanical enforcement (Non-goal), edits to
plugin skills (Non-goal), per-harness dispatch mechanism changes (Non-goal),
retrofitting existing project designs (Non-goal), direct-host sessions
(Non-goal).

**Known deviation to report, not to resolve unilaterally:** the design names
"the consumer `devcontainer.json`" without saying which. This plan declares the
mount in this repo's own `.devcontainer/devcontainer.json` — the only consumer
config the repo contains — and documents the declaration in `NOTES.md` for
out-of-repo consumers, which are untracked host files this PR cannot reach.
