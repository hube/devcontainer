# Git Commit Attribution — Spec Implementation Plan (`hube/claude-home`)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land the trailer-contract spec file and the `CLAUDE.md` contract
changes in `hube/claude-home` — step 1 of the rollout designed in
`hube/devcontainer` `docs/designs/2026-07-10-git-commit-attribution-design.md`
(merged via `hube/devcontainer#38`; rollout tracker `hube/devcontainer#51`).

**Architecture:** One new file (`git-commit-attribution.conf`, the contract's
single source of truth, `mode warn`) plus prose edits making `Skills:`
mandatory with a `none` sentinel and pointing at the spec. No code, no tests
in this repo; the sibling **gate plan**
(`hube/devcontainer` `docs/implementation-plans/2026-08-03-git-commit-attribution-gate-implementation-plan.md`)
embeds this spec byte-for-byte as a Vitest fixture, so both plans copy the
spec **verbatim from the design doc's *The spec* section** — that shared
source is the only coordination point between the two implementation agents.

**Tech Stack:** Plain text + Markdown.

**Repository:** `hube/claude-home` (container checkout:
`/workspaces/agent-devcontainer/claude-home`; on the host this repo *is*
`~/.claude`). Use a fresh linked worktree in that repository.

## Global Constraints

- The design document is the authority. Where this plan and the design
  disagree, stop and report the conflict rather than picking silently.
- The spec lands with `mode warn`. Do not write `enforce`.
- Spec grammar and content are settled (Decided (owner) via the merged
  `hube/devcontainer#38` review): do not add records, comments, or keys.
- Commit style: sentence-case imperative subject. **The commit must itself
  end with the full contiguous trailer block** (`Harness:`,
  `Harness-Version:`, `Model:`, `Skills:`, `Co-Authored-By:` last, no blank
  line inside), verified with
  `git log -1 --pretty=%B | git interpret-trailers --parse`. The gate this
  spec feeds does not exist yet, so the verification is manual and
  mandatory.

---

### Task 1: Spec file and contract pointer

**Files:**
- Create: `git-commit-attribution.conf`
- Modify: `CLAUDE.md` (five passages, exact edits below)

**Interfaces:**
- Produces: the spec file whose byte content the gate plan's parser fixture
  (`LIVE_SPEC` in its Task 1) and integration suite copy verbatim. Both
  derive from the design doc's *The spec* section — if you change even
  whitespace here, you have diverged from the design; stop and report.

- [ ] **Step 1: Create `git-commit-attribution.conf`** with exactly this
  content (from the design's *The spec* section):

```
version      1
mode         warn

trailer      Harness           required
trailer      Harness-Version   required
trailer      Model             required
trailer      Skills            required
trailer      Co-Authored-By    required last

agent-author noreply@anthropic.com
agent-author noreply@openai.com
```

- [ ] **Step 2: Update `CLAUDE.md` — `Skills` becomes mandatory.** Five
  edits; old strings are exact as of `claude-home` `main` (`f782023`):

  1. In the Best practices metadata-block example, replace
     `Skills: <skills used, comma-separated; omit when none>` with
     `Skills: <skills used, comma-separated, or 'none'>`.
  2. Replace the bullet
     ``- `Skills`: only the skills that contributed to producing that artifact;``
     ``omit the `Skills:` line entirely when none did.``
     with
     ``- `Skills`: the skills that contributed to producing that artifact,``
     ``comma-separated, or `none` when no skill did. Always present on commits.``
  3. In "Editing and committing", in the compliant-message example, make the
     same replacement as edit 1 (`omit when none` → `or 'none'`).
  4. Replace ``(`Harness:`, `Harness-Version:`, `Model:`, and `Skills:` when
     applicable)`` with ``(`Harness:`, `Harness-Version:`, `Model:`, and
     `Skills:`)``.
  5. Replace ``every required trailer (`Harness:`, `Harness-Version:`,
     `Model:`, `Skills:` when applicable, and `Co-Authored-By:`)`` with
     ``every required trailer (`Harness:`, `Harness-Version:`, `Model:`,
     `Skills:`, and `Co-Authored-By:`)``.

  Search the whole file for any remaining `omit` near `Skills` afterwards;
  there must be none.

- [ ] **Step 3: Add the spec pointer to `CLAUDE.md`.** Immediately after the
  Best practices metadata-block bullet list (after the `Skills` sub-bullet
  edited above), insert:

```markdown
  The machine-readable contract for this block is
  `~/.claude/git-commit-attribution.conf` (in devcontainers it is mounted
  read-only at
  `/etc/devcontainer/feature/git-commit-attribution/trailer-contract`, where
  a `commit-msg` gate enforces it). The spec file is authoritative; this
  prose describes it.
```

- [ ] **Step 4: Verify.** `git diff` shows only the intended edits; the new
  spec file matches Step 1 byte for byte — record
  `sha256sum git-commit-attribution.conf` in the PR body so the gate plan's
  agent (and any reviewer) can cross-check the fixture without reading this
  repo.

- [ ] **Step 5: Commit** with subject
  `Add the commit-trailer contract spec and make Skills mandatory`, full
  trailer block, then verify with
  `git log -1 --pretty=%B | git interpret-trailers --parse`.

---

## Out of Scope

- Everything in `hube/devcontainer` (validator, dispatcher, Feature, CI):
  the gate plan.
- `hube/agent-skills#9` (producer fix): its own plan in that repository.
- Flipping `mode enforce`: a later host-side edit, tracked in
  `hube/devcontainer#51`, gated on `hube/agent-skills#9`.

## Deployment ordering (orchestrator, not this task)

This PR must be merged and pulled on the host at `~/.claude` **before** any
container is rebuilt with the gate Feature — the gate fails closed on a
missing spec and blocks all commits (design, *Failure Behavior*; tracker
`hube/devcontainer#51`). Development of the two plans is unordered; only
deployment is ordered.
