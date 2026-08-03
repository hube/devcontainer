# Git Commit Attribution — Gate Implementation Plan (`hube/devcontainer`)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the `git-commit-attribution` gate designed in
[`docs/designs/2026-07-10-git-commit-attribution-design.md`](../designs/2026-07-10-git-commit-attribution-design.md)
(merged via `hube/devcontainer#38`): a `commit-msg` hook, installed
container-wide via `core.hooksPath`, that validates the attribution trailer
block on agent-authored commits against a spec bind-mounted from
`hube/claude-home`.

**Architecture:** A TypeScript validator (committed esbuild bundle, invoked by
a POSIX `sh` dispatcher symlinked under every githooks(5) name) reads a
one-record-per-line spec at a fixed FHS path and delegates trailer parsing to
`git interpret-trailers --parse`. The Feature writes `core.hooksPath` to
`/etc/gitconfig` at image build and fails closed when the spec is missing. It
ships in `mode warn`; the `enforce` flip is a later host-side spec edit gated
on `hube/agent-skills#9`.

**Tech Stack:** TypeScript + Vitest + esbuild (mirroring
`hube/agent-skills`), POSIX `sh` / bash shims, devcontainer local Feature,
GitHub Actions.

**Repository:** `hube/devcontainer` only. The spec file itself lands in
`hube/claude-home` under the sibling **spec plan**
([`2026-08-03-git-commit-attribution-spec-implementation-plan.md`](2026-08-03-git-commit-attribution-spec-implementation-plan.md)),
implemented by a separate agent. The two plans are development-independent:
both copy the spec **verbatim from the design doc's *The spec* section**, so
this plan's `LIVE_SPEC` fixture never waits on that PR. Only *deployment* is
ordered (spec on the host before any rebuild — see the end of this plan).

## Global Constraints

- The design document is the authority. Where this plan and the design
  disagree, stop and report the conflict rather than picking silently.
- Spec path (compiled-in default, identical everywhere):
  `/etc/devcontainer/feature/git-commit-attribution/trailer-contract`.
  (The PR #38 review-round commit message once wrote
  `/etc/devcontainer-feature/…` — that was a typo in the commit message; the
  design doc's `/etc/devcontainer/feature/…` is correct and appears four times
  in the merged doc.)
- The landed spec says `mode warn`. Nothing in this plan flips it to
  `enforce`.
- The gate fails closed: missing spec, spec-path-is-a-directory, malformed
  spec, unsupported `version`, unknown record type, and unexecutable validator
  all reject the commit with problem → consequence → remedy messages.
- All contract logic is TypeScript under `src/git-commit-attribution/`; shell
  is limited to `install.sh` (node bootstrap), `dispatch.sh` (hot-path
  router), `postStartScript.sh` (non-blocking warning), and test suites — per
  `docs/feature-authoring.md`.
- `dispatch.sh` is POSIX `sh` — no bashisms (no arrays, no `[[`, no
  `local`). Test scripts and install/postStart scripts are bash, matching
  `local-features/agent-skills`.
- The committed bundle `dist/validate` must be byte-identical to a clean
  rebuild (`npm run build && git diff --exit-code`), with shebang
  `#!/usr/local/bin/node` and no container-specific values. Pin exact
  dependency versions (no `^`/`~`), as `hube/agent-skills/package.json` does.
- Dependency versions: latest as verified via `npm view <pkg> version` on
  2026-08-03 — `typescript` 7.0.2, `esbuild` 0.28.1, `vitest` 4.1.10,
  `eslint` 10.8.0, `typescript-eslint` 8.66.0, `@types/node` 26.1.2. Re-run
  `npm view` at implementation time and take newer patch/minor releases if
  published. If `typescript-eslint`'s peer range rejects TypeScript 7, pin the
  latest TypeScript 6.x instead and record that constraint in a one-line
  comment in `package.json`.
- Test assertions match strings only this code can emit (prefix
  `git-commit-attribution: `), never bare `fatal:`. Every new assertion must
  be observed to **fail** against the code without the change under test
  (write test → run → red → implement → green).
- Commit style: sentence-case imperative subjects matching the repo's history
  (e.g. "Add spec parser for the trailer contract"), no conventional-commit
  prefixes. **Every commit must itself end with the full contiguous trailer
  block** (`Harness:`, `Harness-Version:`, `Model:`, `Skills:`,
  `Co-Authored-By:` last, no blank line inside), verified after each commit
  with `git log -1 --pretty=%B | git interpret-trailers --parse`. The gate
  being built does not yet run in this container, so this verification is
  manual and mandatory.
- Do not modify `mode` handling, hook names, or spec grammar beyond what the
  design states. `Subagents:` is a reserved future extension — do not
  implement it.

## Settled Decisions (do not reopen)

All `Decided (owner)` via the merged PR #38 review
(<https://github.com/hube/devcontainer/pull/38>):

- `Skills:` is mandatory with a `none` sentinel.
- Spec lives in `hube/claude-home`, mounted read-only by the **consumer**
  (`devcontainer.json`), not by the Feature; fixed FHS path under `/etc`.
- Trigger reads raw text; validator delegates to
  `git interpret-trailers --parse`.
- `core.hooksPath` in `/etc/gitconfig`, written by `install.sh` at image
  build (the git-config placement rule in `docs/feature-authoring.md`).
- Chaining dispatcher over every githooks(5) name, with adapters for
  `push-to-checkout` and `proc-receive`.
- TypeScript validator, committed dependency-free bundle, Feature-owned
  `node:2` dependency, `/usr/local/bin/node` symlink.
- Fail closed, including during warn rollout; `--no-verify` is the documented
  escape.
- Warn-then-enforce rollout (`hube/devcontainer#51`); enforce is gated on
  `hube/agent-skills#9`.

## File Structure

```
package.json  tsconfig.json  vitest.config.ts  eslint.config.mjs   new
scripts/build.mjs                                                  new
src/git-commit-attribution/spec.ts       spec parsing
src/git-commit-attribution/trailers.ts   trigger, parse, sequence compare
src/git-commit-attribution/validate.ts   orchestration, modes, messages
src/git-commit-attribution/cli.ts        argv dispatch, default spec path
tests-vitest/git-commit-attribution/*.test.ts
.devcontainer/local-features/git-commit-attribution/
  devcontainer-feature.json   dependsOn node:2, postStartCommand
  install.sh                  symlink farm, node symlink, /etc/gitconfig
  dispatch.sh                 POSIX dispatcher + adapters
  dist/validate               committed bundle (build output)
  NOTES.md                    bypasses, hook-list policy, consumer mount
  bin/devcontainer-feature/git-commit-attribution/postStartScript.sh
  test/test-dispatch.sh       dispatcher behavior (stub validator)
  test/test-poststart.sh      postStart warning branches
  test/test-install-order.sh  dependsOn ordering + postStartCommand
  test/test-integration.sh    end-to-end commits in the built image
  test/test-codex-sandbox.sh  in-container Codex sandbox probe (manual)
.devcontainer/devcontainer.json   edit — Feature stanza + spec mount
.github/workflows/tests.yml       new — first test CI for this repo
docs/designs/2026-07-10-git-commit-attribution-design.md   status edits
```

---

### Task 1: Toolchain scaffold and spec parser (`spec.ts`)

**Files:**
- Create: `package.json`, `tsconfig.json`, `vitest.config.ts`,
  `eslint.config.mjs`, `scripts/build.mjs`,
  `src/git-commit-attribution/spec.ts`
- Test: `tests-vitest/git-commit-attribution/spec.test.ts`

**Interfaces:**
- Produces (consumed by Tasks 2–5):

```ts
// src/git-commit-attribution/spec.ts
export const SUPPORTED_SPEC_VERSION = 1;
export type SpecMode = 'warn' | 'enforce';
export interface TrailerRule { key: string; last: boolean }
export interface Spec {
  version: number;
  mode: SpecMode;
  trailers: TrailerRule[];   // in spec order; exactly one rule has last=true
  agentAuthors: string[];    // lowercased addresses
}
export type SpecParseResult =
  | { ok: true; spec: Spec }
  | { ok: false; problem: string };  // names the offending line and its text
export function parseSpec(text: string): SpecParseResult;
```

- [ ] **Step 1: Scaffold the toolchain**, mirroring
  `hube/agent-skills` (`package.json` scripts, strict `tsconfig`, flat eslint
  config). `package.json`:

```json
{
  "name": "hube-devcontainer-tooling",
  "private": true,
  "engines": { "node": ">=18.17" },
  "scripts": {
    "build": "node scripts/build.mjs",
    "typecheck": "tsc --noEmit",
    "lint": "eslint src scripts tests-vitest",
    "test": "vitest run"
  },
  "devDependencies": {
    "@types/node": "26.1.2",
    "esbuild": "0.28.1",
    "eslint": "10.8.0",
    "typescript": "7.0.2",
    "typescript-eslint": "8.66.0",
    "vitest": "4.1.10"
  }
}
```

  (Versions per Global Constraints — re-check `npm view` first.)
  `tsconfig.json`: copy `hube/agent-skills/tsconfig.json` verbatim (targets
  ES2022, strict, noEmit, includes `src`, `tests-vitest`,
  `vitest.config.ts`). `eslint.config.mjs`: flat config with
  `typescript-eslint` recommended, covering `src`, `scripts`,
  `tests-vitest`. `scripts/build.mjs` (final form; nothing to add later):

```js
import { build } from 'esbuild';
import { chmodSync } from 'node:fs';

const OUTFILE =
  '.devcontainer/local-features/git-commit-attribution/dist/validate';

await build({
  entryPoints: ['src/git-commit-attribution/cli.ts'],
  outfile: OUTFILE,
  bundle: true,
  platform: 'node',
  format: 'cjs',
  target: 'node18',
  // Fixed interpreter path: install.sh guarantees this symlink, so the
  // committed bundle carries no container-specific value (design, *Node*).
  banner: { js: '#!/usr/local/bin/node' },
  legalComments: 'none',
});
chmodSync(OUTFILE, 0o755);
console.log(`built ${OUTFILE}`);
```

  `npm install`, then verify `npm run typecheck` and `npm run lint` pass on
  the empty scaffold (create `src/git-commit-attribution/spec.ts` with just
  the exported constant first so tsc has input).

- [ ] **Step 2: Write failing spec-parser tests** in
  `tests-vitest/git-commit-attribution/spec.test.ts`. Include, at minimum:

```ts
import { describe, expect, it } from 'vitest';
import { parseSpec } from '../../src/git-commit-attribution/spec';

// Byte-identical to the design doc's *The spec* section — and therefore to
// hube/claude-home's git-commit-attribution.conf (the sibling spec plan).
const LIVE_SPEC = `version      1
mode         warn

trailer      Harness           required
trailer      Harness-Version   required
trailer      Model             required
trailer      Skills            required
trailer      Co-Authored-By    required last

agent-author noreply@anthropic.com
agent-author noreply@openai.com
`;

describe('parseSpec', () => {
  it('parses the live contract', () => {
    const r = parseSpec(LIVE_SPEC);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.spec.version).toBe(1);
    expect(r.spec.mode).toBe('warn');
    expect(r.spec.trailers.map((t) => t.key)).toEqual([
      'Harness', 'Harness-Version', 'Model', 'Skills', 'Co-Authored-By',
    ]);
    expect(r.spec.trailers.map((t) => t.last)).toEqual([
      false, false, false, false, true,
    ]);
    expect(r.spec.agentAuthors).toEqual([
      'noreply@anthropic.com', 'noreply@openai.com',
    ]);
  });
  it('parses mode enforce', () => { /* LIVE_SPEC with mode enforce */ });
  it('rejects an unsupported version, naming the remedy', () => {
    const r = parseSpec(LIVE_SPEC.replace('version      1', 'version      2'));
    expect(r.ok).toBe(false);
    if (r.ok) return;
    expect(r.problem).toContain('version 2');
    expect(r.problem).toContain('rebuild the container');
  });
  it('rejects an unknown record type, naming the line', () => {
    const r = parseSpec(LIVE_SPEC + 'trailler Foo required\n');
    expect(r.ok).toBe(false);
    if (r.ok) return;
    expect(r.problem).toContain('trailler Foo required');
  });
  it('rejects a trailer record with an unknown modifier', () => {
    // "optional" is not in the v1 grammar
    const r = parseSpec(LIVE_SPEC.replace('Skills            required',
      'Skills            optional'));
    expect(r.ok).toBe(false);
  });
  it('rejects when last is not on the final trailer record', () => { /* move
    'last' onto Model */ });
  it('rejects a missing mode, a missing version, and an empty spec', () => {
    /* three sub-cases, each ok:false */ });
  it('rejects a duplicate trailer key in the spec', () => { /* second
    'trailer Model required' line */ });
});
```

  Fill the elided bodies with real assertions of the same shape.

- [ ] **Step 3: Run tests, confirm they fail** (module has no `parseSpec`):
  `npm test -- spec` → FAIL.

- [ ] **Step 4: Implement `parseSpec`.** Grammar (v1): split into lines; skip
  blank lines; each non-blank line is whitespace-separated fields. Records:
  `version <int>` (required, must be `SUPPORTED_SPEC_VERSION` — a different
  int yields
  `problem: "spec declares version N, but this validator supports version 1 — rebuild the container to update the validator, or pin the spec to the older grammar"`),
  `mode warn|enforce` (required), `trailer <Key> required [last]` (at least
  one; any other modifier token rejects; `last` only valid on the final
  trailer record; duplicate keys reject), `agent-author <address>` (at least
  one; lowercased on parse). Any other first field rejects, quoting the line.
  No comment syntax exists in v1 — a `#` line is an unknown record and
  rejects (a typo'd record must not silently weaken a control).

- [ ] **Step 5: Run tests to green**: `npm test -- spec` → PASS. Also
  `npm run typecheck && npm run lint` → PASS.

- [ ] **Step 6: Commit**
  `Add toolchain scaffold and trailer-contract spec parser` (+ trailer
  block; verify with `git interpret-trailers --parse`).

---

### Task 2: Trigger detection (`trailers.ts`, part 1)

**Files:**
- Create: `src/git-commit-attribution/trailers.ts`
- Test: `tests-vitest/git-commit-attribution/trigger.test.ts`

**Interfaces:**
- Consumes: `Spec` from Task 1.
- Produces (consumed by Task 4):

```ts
// src/git-commit-attribution/trailers.ts
export function triggers(rawMessage: string, spec: Spec): boolean;
```

- [ ] **Step 1: Write failing trigger tests.** The trigger reads **raw text**
  (design, *Validation Flow*): it fires when any line matches `^<Key>:` for a
  spec trailer key other than the `last` one, or `^Co-Authored-By:` whose
  line contains (case-insensitively) an `agent-author` address. Cases:

```ts
const spec = mustParse(LIVE_SPEC); // helper: parseSpec + throw on !ok

it('fires on a well-formed agent block', ...);         // full 5-trailer msg
it('fires on a malformed block (prose line above it)', () => {
  // This is the load-bearing case: parsed output would be empty, raw text
  // still matches ^Harness:. Message:
  // "subject\n\nSome prose.\nHarness: Claude Code\n...block..."
});
it('fires on Co-Authored-By with an agent address only', ...);
  // "subject\n\nCo-Authored-By: claude-opus-4-8 <noreply@anthropic.com>"
  // (worklog-contribute's real current output — src/worklog/git.ts)
it('does not fire on human-to-human Co-Authored-By', ...);
  // "Co-Authored-By: Alex Doe <alex@example.com>"
it('does not fire on a message with no trailers at all', ...);
it('does not fire on "Harness:" mid-line (not at line start)', ...);
it('is generated from the spec: a key added to the spec trips it', () => {
  // parse LIVE_SPEC + "trailer Subagents required" (inserted before the
  // last record) and assert "Subagents: x" fires
});
```

- [ ] **Step 2: Run to red**: `npm test -- trigger` → FAIL.

- [ ] **Step 3: Implement `triggers`.** Build patterns from
  `spec.trailers`/`spec.agentAuthors` at call time (no hardcoded key list;
  escape regex metacharacters in keys). Match with `m` flag on the raw
  message.

- [ ] **Step 4: Run to green**, plus typecheck + lint.

- [ ] **Step 5: Commit** `Add raw-text trigger detection for the gate`
  (+ trailer block, verified).

---

### Task 3: Trailer parsing and sequence comparison (`trailers.ts`, part 2)

**Files:**
- Modify: `src/git-commit-attribution/trailers.ts`
- Test: `tests-vitest/git-commit-attribution/sequence.test.ts`

**Interfaces:**
- Produces (consumed by Task 4):

```ts
export interface Trailer { key: string; value: string }
// Shells out to: git interpret-trailers --parse   (message on stdin).
// Git's parse IS the contract's parse — no reimplementation (design,
// *Validation Flow*). Uses node:child_process.spawnSync('git', ...).
export function parseTrailers(rawMessage: string): Trailer[];
// Returns [] when compliant; otherwise one problem string per defect,
// e.g. "missing the required trailer 'Skills'".
export function compareSequence(trailers: Trailer[], spec: Spec): string[];
```

- [ ] **Step 1: Write failing tests.** `parseTrailers` runs real git (the
  suite runs where git ≥ 2.53 is installed; do not mock — the design's
  guarantee is agreement with git). Sequence semantics (design, *Sequence
  Semantics*):

  - each required key except the `last` one appears **exactly once in the
    entire trailer list**;
  - the parsed list **ends** with the block: the required keys in spec order,
    contiguous, then one-or-more `Co-Authored-By` closing the list;
  - any `Co-Authored-By` outside that terminal run is a violation;
  - unlisted trailers (`Signed-off-by`, `Change-Id`) are permitted strictly
    **before** the block.

  Message-level fixtures (each a full commit message string; expected result
  from the design's *Testing* table):

```
reject  #23's fabricated block (no Skills:):
        "Enhance issue\n\nHarness: Claude Code\nHarness-Version: 2.1.205 (Claude Code)\nModel: claude-haiku-4-5-20251001\nCo-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>\n"
pass    #23's amended block (adds "Skills: superpowers:subagent-driven-development" before Co-Authored-By)
reject  a Codex-style block with Model: gpt-5 and no Skills:
        (representative of hube/devcontainer#15; construct with
        Harness: Codex CLI / Harness-Version: 0.144.5 / Model: gpt-5 /
        Co-Authored-By: GPT-5 <noreply@openai.com>)
pass    the same Codex block with "Skills: none" inserted
reject  blank line splitting the block (git parses only the tail → missing keys)
reject  prose line inside the block (git parses zero trailers → all missing)
reject  Co-Authored-By not last (Skills after it)
pass    repeated Co-Authored-By ending the block (two harness co-authors)
reject  duplicate Model: elsewhere in the trailer list
reject  two complete attribution blocks, one valid
pass    Signed-off-by before the block
reject  Signed-off-by after Co-Authored-By (what git commit --signoff produces)
```

  For the two "git parses nothing/tail" cases, also assert `parseTrailers`'s
  own output directly (empty list / tail-only list) — that pins the verified
  behavior the design relies on.

- [ ] **Step 2: Run to red.**

- [ ] **Step 3: Implement.** `parseTrailers`: `spawnSync('git',
  ['interpret-trailers', '--parse'], { input: rawMessage })`; split stdout
  lines on the first `: ` into `{key, value}`; a non-zero git exit throws
  (the caller converts to a fail-closed rejection in Task 4).
  `compareSequence` algorithm: (1) count occurrences of each non-last
  required key — `!== 1` yields "missing"/"duplicate" problems; count of the
  last key `< 1` yields "missing"; report all such problems, and if any key
  is missing entirely, stop there (order checks against absent keys add
  noise). (2) Otherwise locate the first required key's index; from there to
  the end of the list, the keys must be exactly the non-last required keys in
  spec order followed by ≥1 of the last key — any intruding unlisted key, any
  misorder, or the list not ending with the last key yields a problem naming
  the offending trailer. (3) Any occurrence of the last key before that
  terminal run yields "Co-Authored-By must end the attribution block".

- [ ] **Step 4: Run to green**, typecheck, lint.

- [ ] **Step 5: Commit** `Parse trailers via git and compare the required
  sequence` (+ trailer block, verified).

---

### Task 4: Validation orchestration and messages (`validate.ts`)

**Files:**
- Create: `src/git-commit-attribution/validate.ts`
- Test: `tests-vitest/git-commit-attribution/validate.test.ts`

**Interfaces:**
- Consumes: `parseSpec`, `triggers`, `parseTrailers`, `compareSequence`.
- Produces (consumed by Task 5):

```ts
// validate.ts
export interface Outcome { exitCode: 0 | 1; stderr: string[] }
// Reads + parses the spec file; fail closed on any defect.
export function loadSpec(specPath: string):
  | { ok: true; spec: Spec }
  | { ok: false; outcome: Outcome };
// Full pipeline for one message (trigger → parse → compare → mode).
export function checkMessage(raw: string, spec: Spec, specPath: string): Outcome;
export function runCommitMsg(msgfile: string, specPath: string): Outcome;
export function runRange(range: string, specPath: string): Outcome;
```

- [ ] **Step 1: Write failing tests.** Spec-file handling (use `mktemp`-style
  tmp dirs via `node:fs`):

```
spec file missing        → exit 1; stderr includes the spec path and
                           "The commit was not created."
spec path is a directory → exit 1; same shape ("not a file")
spec malformed           → exit 1; names the offending line
spec version unsupported → exit 1; names the remedy (rebuild / pin)
```

  Message handling (spec = LIVE_SPEC in a tmp file):

```
no trigger               → exit 0, stderr empty (silent pass)
violation, mode enforce  → exit 1; stderr matches the design's rejection
                           template (see below)
violation, mode warn     → exit 0; stderr contains "WARNING", the same
                           diagnosis, and "will become an error"
compliant block          → exit 0, stderr empty
```

  The enforce rejection must follow the design's template exactly
  (problem → consequence → remedy, then the contract, then the spec path):

```
git-commit-attribution: commit message is missing the required trailer 'Skills'.
The commit was not created.
Agent-authored commits must end with this contiguous block, Co-Authored-By last:

  Harness: <harness>
  Harness-Version: <version>
  Model: <model id>
  Skills: <skills used, comma-separated, or 'none'>
  Co-Authored-By: <model display name> <noreply address>

Spec: <the specPath the validator was invoked with>
```

  With multiple problems, the first line lists each problem on its own
  `git-commit-attribution: ` line; the consequence/remedy/contract section
  appears once. Range mode: build a scratch git repo in the test
  (`spawnSync` git init/commit), commit one compliant and one violating
  message (no hooks exist in a fresh tmp repo, so commits land unimpeded),
  then assert `runRange('HEAD~2..HEAD', specPath)` reports the violating sha
  and exits 1 under `mode enforce`, 0 under `mode warn`.

- [ ] **Step 2: Run to red.**

- [ ] **Step 3: Implement.** `loadSpec`: `statSync` (missing → problem
  "no spec at <path>", consequence "every commit is rejected until it
  exists", remedy "mount ~/.claude/git-commit-attribution.conf — a checkout
  of hube/claude-home — to this path, or bypass once with git commit
  --no-verify"); non-file → analogous; then `parseSpec`. `checkMessage`:
  trigger; if fired, `parseTrailers` + `compareSequence`; mode decides
  exit 1 (enforce) vs exit 0 with WARNING prefix (warn). `runCommitMsg`:
  `readFileSync(msgfile)` → `checkMessage`. `runRange`: `git rev-list
  --reverse <range>`, then per sha `git log -1 --format=%B <sha>` →
  `checkMessage`, prefixing each stderr line with the abbreviated sha.

- [ ] **Step 4: Run to green**, typecheck, lint.

- [ ] **Step 5: Commit** `Add fail-closed validation pipeline and rejection
  messages` (+ trailer block, verified).

---

### Task 5: CLI entry point and the committed bundle (`cli.ts`, `dist/validate`)

**Files:**
- Create: `src/git-commit-attribution/cli.ts`
- Create (build output, committed): `.devcontainer/local-features/git-commit-attribution/dist/validate`
- Test: `tests-vitest/git-commit-attribution/cli.test.ts`

**Interfaces:**
- Produces: the `validate` executable with two entry forms —
  `validate commit-msg <msgfile>` (dispatcher; compiled-in default spec
  path) and `validate --range BASE..HEAD --spec PATH` (CI). Consumed by
  Tasks 6–9.

```ts
// cli.ts
export const DEFAULT_SPEC_PATH =
  '/etc/devcontainer/feature/git-commit-attribution/trailer-contract';
export function main(argv: string[]): number;  // argv = process.argv.slice(2)
```

- [ ] **Step 1: Write failing CLI tests** (call `main` directly):

```
['commit-msg', msgfile]                    → uses DEFAULT_SPEC_PATH (assert by
                                             the path appearing in the
                                             missing-spec rejection on a
                                             machine without the mount)
['commit-msg', msgfile, '--spec', p]       → uses p (CI/test override)
['--range', 'A..B', '--spec', p]           → range mode against p
['--range', 'A..B']                        → range mode against DEFAULT_SPEC_PATH
[]                                         → exit 1, usage on stderr
['bogus']                                  → exit 1, usage names both forms
```

- [ ] **Step 2: Run to red.**

- [ ] **Step 3: Implement `main`** (validate all argv problems together and
  report each, per the validating-input convention), plus the module tail:

```ts
if (require.main === module) {
  process.exitCode = main(process.argv.slice(2));
}
```

  (`main` prints the `Outcome.stderr` lines to `process.stderr` and returns
  `Outcome.exitCode`.)

- [ ] **Step 4: Run to green**, typecheck, lint.

- [ ] **Step 5: Build and commit the bundle.** `npm run build`; verify
  `head -1 .devcontainer/local-features/git-commit-attribution/dist/validate`
  is exactly `#!/usr/local/bin/node`; verify the bundle imports only `node:`
  builtins; run it once end-to-end:
  `printf 'x\n' > /tmp/m && dist/validate commit-msg /tmp/m --spec <tmp spec>`
  → exit 0. Rebuild and confirm determinism:
  `npm run build && git diff --exit-code -- .devcontainer/local-features/git-commit-attribution/dist/`.

- [ ] **Step 6: Commit** `Add the validator CLI and committed bundle`
  (+ trailer block, verified). The bundle is part of this commit.

---

### Task 6: The hook dispatcher (`dispatch.sh`)

**Files:**
- Create: `.devcontainer/local-features/git-commit-attribution/dispatch.sh`
- Test: `.devcontainer/local-features/git-commit-attribution/test/test-dispatch.sh`

**Interfaces:**
- Consumes: the validator invocation contract `validate commit-msg <msgfile>`
  (Task 5). For these tests the validator is a **stub** so dispatcher logic is
  isolated; the real bundle is exercised in Task 8.
- Produces: a static POSIX `sh` script installed (Task 7) as
  `/usr/local/share/git-commit-attribution/hooks/dispatch`, symlinked under
  every githooks(5) name.

- [ ] **Step 1: Write the failing bash suite** `test/test-dispatch.sh`,
  following the `pass()`/`fail()`/`setup_world` idiom of
  `local-features/agent-skills/test/test-poststart.sh`. The world: a tmp
  `GATE_DIR` holding `dispatch` + symlinks (built exactly as `install.sh`
  will), a stub `validate` whose exit code and output the test controls, and
  scratch git repos steered with `GIT_CONFIG_SYSTEM=$WORLD/gitconfig`
  containing `[core] hooksPath = $GATE_DIR/hooks`. For the interpreter check
  the stub world also provides a fake node substitute — the dispatcher reads
  `GCA_ROOT="${GCA_ROOT:-/usr/local/share/git-commit-attribution}"` and
  `GCA_NODE="${GCA_NODE:-/usr/local/bin/node}"` (two env seams, defaulted,
  no other configurability). Cases, each asserted on strings only this code
  emits and on ref/worktree state:

```
chains: repo .git/hooks/pre-commit runs (marker file) and its non-zero
  status blocks the commit
repo commit-msg runs after a validator PASS; its non-zero status blocks
repo hook present but not executable → "exists but is not executable"
  warning; treated as absent; commit succeeds
commit-msg, stub validator exits 1 → commit not created; validator stderr
  reached the user
commit-msg, stub validator exits 0, no repo hook → commit created
validator missing/not executable → commit rejected; message names what it
  could not run ("cannot execute"), and the remedy (rebuild / --no-verify)
non-commit-msg hooks never invoke the validator (stub records invocations;
  a plain `git add`+`pre-commit` path must not touch it)
git commit --no-verify with a rejecting stub → commit created (bypass)
linked worktree: git worktree add, repo hook in main .git/hooks runs for a
  commit made in the worktree (--git-common-dir resolution)
push-to-checkout, receive.denyCurrentBranch=updateInstead, clean target,
  no repo hook → push accepted; target worktree+index equal pushed tip;
  `git -C target status --porcelain` empty
same, dirty target worktree → push refused; ref unmoved; local edit intact
same, repo push-to-checkout hook present → repo hook runs (marker)
proc-receive: push to a ref matched by receive.procReceiveRefs with no repo
  hook → push rejected (remote rejects the ref), mirroring an absent hook
```

- [ ] **Step 2: Run to red** (`bash test/test-dispatch.sh` — fails: no
  `dispatch.sh`).

- [ ] **Step 3: Write `dispatch.sh`:**

```sh
#!/bin/sh
# Dispatcher for the git-commit-attribution gate. A container-wide
# core.hooksPath replaces the hook directory for EVERY hook git knows, so
# this script is symlinked under every githooks(5) name and chains to the
# repository's own hook. See NOTES.md for the classification rule new hook
# names must pass before joining the symlink farm.
set -u

# Test seams only; both default to the installed locations.
GCA_ROOT="${GCA_ROOT:-/usr/local/share/git-commit-attribution}"
GCA_NODE="${GCA_NODE:-/usr/local/bin/node}"

hook_name=$(basename "$0")

if [ "$hook_name" = "commit-msg" ]; then
  validator="$GCA_ROOT/validate"
  if [ -x "$validator" ] && [ -x "$GCA_NODE" ]; then
    "$validator" commit-msg "$1" || exit $?
  else
    echo "git-commit-attribution: cannot execute the validator at $validator (interpreter: $GCA_NODE)." >&2
    echo "The commit was not created: the gate fails closed when it cannot run." >&2
    echo "Remedy: rebuild the container; to bypass once, use git commit --no-verify." >&2
    exit 1
  fi
fi

# --git-common-dir ignores core.hooksPath (the recursion guard) and, from a
# linked worktree where .git is a file, resolves the main repository's .git,
# where hooks actually live.
repo_hook="$(git rev-parse --git-common-dir)/hooks/$hook_name"

if [ -x "$repo_hook" ]; then
  exec "$repo_hook" "$@"
fi

if [ -f "$repo_hook" ]; then
  echo "git-commit-attribution: hook '$repo_hook' exists but is not executable; ignoring it." >&2
fi

case "$hook_name" in
  push-to-checkout)
    # Presence-sensitive: exit 0 would tell git the worktree update was
    # handled. Emulate git's built-in updateInstead default instead: refuse
    # when worktree or index differ from HEAD, otherwise update both. The
    # cwd here is $GIT_DIR, which contains a file named HEAD, so the -- on
    # diff-index disambiguates the revision from that file.
    git update-index -q --ignore-submodules --refresh &&
    git diff-files --quiet --ignore-submodules -- &&
    git diff-index --quiet --cached --ignore-submodules HEAD -- &&
    git read-tree -u -m HEAD "$1"
    exit $?
    ;;
  proc-receive)
    # Presence-sensitive: speaks a pkt-line protocol no generic script can
    # emulate. Failing rejects the matched ref exactly as an absent hook
    # does; exit 0 would claim refs were handled when nothing handled them.
    exit 1
    ;;
  *)
    exit 0
    ;;
esac
```

- [ ] **Step 4: Run to green.** Also `shellcheck --shell=sh dispatch.sh`
  (install shellcheck if absent; fix findings or record a justified disable
  inline).

- [ ] **Step 5: Commit** `Add the chaining hook dispatcher with
  presence-sensitive adapters` (+ trailer block, verified).

---

### Task 7: Feature packaging (`install.sh`, manifest, postStart, NOTES)

**Files:**
- Create: `.devcontainer/local-features/git-commit-attribution/devcontainer-feature.json`
- Create: `.devcontainer/local-features/git-commit-attribution/install.sh`
- Create: `.devcontainer/local-features/git-commit-attribution/bin/devcontainer-feature/git-commit-attribution/postStartScript.sh`
- Create: `.devcontainer/local-features/git-commit-attribution/NOTES.md`
- Test: `.devcontainer/local-features/git-commit-attribution/test/test-poststart.sh`

**Interfaces:**
- Consumes: `dispatch.sh` (Task 6), `dist/validate` (Task 5).
- Produces: the installable Feature. Consumer wiring happens in Task 8.

- [ ] **Step 1: Write the failing postStart suite** `test/test-poststart.sh`
  (same idiom as agent-skills'). The script under test takes its spec path
  and scan root from `GCA_SPEC_PATH` / `GCA_SCAN_ROOT` env seams (defaulted
  to `/etc/devcontainer/feature/git-commit-attribution/trailer-contract` and
  `/workspaces`). Cases:

```
spec file present, no shadowing repos → no output, exit 0
spec missing → warning names the container path AND the host-side remedy
  (mount ~/.claude/git-commit-attribution.conf; ensure the host file is a
  checkout of hube/claude-home, not a Docker-created directory); exit 0
spec path is a directory → same warning shape ("not a file"); exit 0
a repo under the scan root with a local core.hooksPath → named, with its
  hooksPath value; exit 0
non-repo directories under the scan root are skipped silently
the script never exits non-zero (assert exit 0 in every case)
```

- [ ] **Step 2: Run to red.**

- [ ] **Step 3: Write `postStartScript.sh`** (bash; never blocks container
  start):

```bash
#!/usr/bin/env bash
# Warns about a missing trailer contract and about repositories whose local
# core.hooksPath shadows the gate. Never fails container start.
set -uo pipefail

SPEC="${GCA_SPEC_PATH:-/etc/devcontainer/feature/git-commit-attribution/trailer-contract}"
SCAN_ROOT="${GCA_SCAN_ROOT:-/workspaces}"

if [[ ! -f "$SPEC" ]]; then
  echo "git-commit-attribution: no trailer contract at $SPEC." >&2
  echo "Every commit in this container will be rejected until it exists (the gate fails closed); git commit --no-verify bypasses one commit." >&2
  echo "Remedy: declare the bind mount in devcontainer.json — \${localEnv:HOME}/.claude/git-commit-attribution.conf -> $SPEC — and ensure the host file exists as part of a hube/claude-home checkout at ~/.claude. If Docker created a directory at the host path, remove it and pull claude-home." >&2
fi

if [[ -d "$SCAN_ROOT" ]]; then
  for repo in "$SCAN_ROOT"/*/; do
    [[ -d "$repo" ]] || continue
    if git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      local_path="$(git -C "$repo" config --local --get core.hooksPath 2>/dev/null || true)"
      if [[ -n "$local_path" ]]; then
        echo "git-commit-attribution: $repo sets core.hooksPath=$local_path locally; the gate is silently bypassed there." >&2
      fi
    fi
  done
fi

exit 0
```

- [ ] **Step 4: Run postStart suite to green.**

- [ ] **Step 5: Write `devcontainer-feature.json`:**

```jsonc
{
  "id": "git-commit-attribution",
  "name": "Git commit attribution gate",
  "version": "1.0.0",
  "description": "commit-msg gate enforcing the attribution trailer contract. The consumer must bind-mount the contract read-only; see NOTES.md.",
  "dependsOn": {
    // The gate must not inherit node's liveness from a cosmetic Feature
    // (ccstatusline); it owns its own interpreter dependency.
    "ghcr.io/devcontainers/features/node:2": {}
  },
  "postStartCommand": "~/bin/devcontainer-feature/git-commit-attribution/postStartScript.sh"
}
```

- [ ] **Step 6: Write `install.sh`** (bash, runs as root at image build):

```bash
#!/usr/bin/env bash
set -euo pipefail

SHARE=/usr/local/share/git-commit-attribution
HOOKS="$SHARE/hooks"

# Hook names from githooks(5) of git 2.53 (the image's git). A name added by
# a future git version must be classified absence-equivalent-or-adapter
# before joining this list — see NOTES.md.
HOOK_NAMES=(
  applypatch-msg pre-applypatch post-applypatch
  pre-commit pre-merge-commit prepare-commit-msg commit-msg post-commit
  pre-rebase post-checkout post-merge pre-push
  pre-receive update proc-receive post-receive post-update
  reference-transaction push-to-checkout pre-auto-gc post-rewrite
  sendemail-validate fsmonitor-watchman
  p4-changelist p4-prepare-changelist p4-post-changelist p4-pre-submit
  post-index-change
)

# Node bootstrap: the committed bundle's shebang is /usr/local/bin/node.
NODE_TARGET=/usr/local/share/nvm/current/bin/node
if [[ ! -x "$NODE_TARGET" ]]; then
  echo "git-commit-attribution: $NODE_TARGET is not executable." >&2
  echo "Every commit in the container depends on this interpreter, so the gate cannot install." >&2
  echo "Remedy: ensure ghcr.io/devcontainers/features/node:2 installs before this Feature (dependsOn)." >&2
  exit 1
fi
ln -sfn "$NODE_TARGET" /usr/local/bin/node
[[ -x /usr/local/bin/node ]]

install -d -m 0755 "$SHARE" "$HOOKS"
# Copied verbatim: no substitution touches either artifact (the spec path
# and shebang are compiled in), which is what keeps the committed bundle
# byte-identical to a clean rebuild.
install -m 0755 dispatch.sh "$HOOKS/dispatch"
install -m 0755 dist/validate "$SHARE/validate"

for name in "${HOOK_NAMES[@]}"; do
  ln -sfn "$HOOKS/dispatch" "$HOOKS/$name"
done

# Control setting → system scope at image build (docs/feature-authoring.md:
# silent absence would mean a false belief the gate is active).
git config --file /etc/gitconfig core.hooksPath "$HOOKS"
chmod 0644 /etc/gitconfig

# postStart warning script, owned by the container user.
user_home="/home/${_CONTAINER_USER}"
rsync -rp \
    --chown="${_CONTAINER_USER}:${_CONTAINER_USER}" \
    --chmod=D755,F755 \
    bin "${user_home}"

echo ">git-commit-attribution installed: hooksPath=$HOOKS, spec expected at /etc/devcontainer/feature/git-commit-attribution/trailer-contract"
```

- [ ] **Step 7: Write `NOTES.md`.** Sections (state each plainly, in this
  order): **Behavior** (what the gate checks, warn vs enforce from the spec's
  `mode`, fail-closed rule); **Consumer mount** — the Feature owns the
  container path only; the consumer declares (copy this block into the doc):

```jsonc
{
  "type": "bind,readonly",
  "source": "${localEnv:HOME}/.claude/git-commit-attribution.conf",
  "target": "/etc/devcontainer/feature/git-commit-attribution/trailer-contract"
}
```

  with the rationale (Feature options cannot interpolate into mount
  declarations; a Codex-only consumer supplies its own source path);
  **Bypasses** — the four from the design, verbatim in intent: a repo-local
  `core.hooksPath` (husky/lefthook/pre-commit) bypasses silently and
  postStart names such repos; `git commit --no-verify` (also the documented
  escape when the spec is broken); commits made outside the container;
  `GIT_CONFIG_NOSYSTEM=1` (live in this container's tooling via the
  security-guidance plugin hook, currently only on a non-committing path);
  **Hook-name policy** — the symlink list is githooks(5) of git 2.53; a new
  hook name must be classified absence-equivalent-or-adapter before joining;
  `push-to-checkout` and `proc-receive` adapters and why (presence-sensitive);
  **Failure handling** — never blocks container start; missing spec warns at
  postStart and rejects at commit time.

- [ ] **Step 8: Verify hook list.** Cross-check `HOOK_NAMES` against
  githooks(5) for the image's git (`git --version` → 2.53.0;
  <https://git-scm.com/docs/githooks/2.53.0>). Every documented hook name
  must appear exactly once; no extras. Record in the PR body that this check
  was done and how.

- [ ] **Step 9: Run the full local suite** — `bash test/test-dispatch.sh`,
  `bash test/test-poststart.sh`, `npm test`, typecheck, lint, shellcheck on
  `install.sh` + `postStartScript.sh` → all green.

- [ ] **Step 10: Commit** `Package the git-commit-attribution local Feature`
  (+ trailer block, verified).

---

### Task 8: Consumer wiring and end-to-end integration

**Files:**
- Modify: `.devcontainer/devcontainer.json`
- Test: `.devcontainer/local-features/git-commit-attribution/test/test-install-order.sh`
- Test: `.devcontainer/local-features/git-commit-attribution/test/test-integration.sh`

**Interfaces:**
- Consumes: the packaged Feature (Task 7), the spec content (design doc /
  sibling spec plan).
- Produces: the image every later verification (Task 10, rollout) runs in.

- [ ] **Step 1: Edit `devcontainer.json`.** Add to `features` (between
  `./local-features/direnv` and `./local-features/github-cli-config` —
  the map is alphabetical):

```jsonc
"./local-features/git-commit-attribution": {},
```

  Add a top-level `mounts` array (the file has none today) after
  `containerUser`:

```jsonc
"mounts": [
  // Trailer contract for the git-commit-attribution gate. The Feature owns
  // the container path; the consumer owns this mount — see the Feature's
  // NOTES.md. Read-only: editing the contract you are judged against would
  // be the one bypass that leaves no trace in the commit.
  {
    "type": "bind,readonly",
    "source": "${localEnv:HOME}/.claude/git-commit-attribution.conf",
    "target": "/etc/devcontainer/feature/git-commit-attribution/trailer-contract"
  }
],
```

  (`"type": "bind,readonly"` is the idiom `local-features/ssh` established.)

- [ ] **Step 2: Write `test-install-order.sh`**, adapted from
  `local-features/agent-skills/test/test-install-order.sh` (devcontainers CLI
  `build`, then inspect the `devcontainer.metadata` label): assert
  `ghcr.io/devcontainers/features/node` appears and installs **before**
  `./local-features/git-commit-attribution`; assert exactly one
  git-commit-attribution metadata entry with `postStartCommand` equal to
  `~/bin/devcontainer-feature/git-commit-attribution/postStartScript.sh`.
  Run it: it must fail before Step 1's edit is correct and pass after
  (temporarily stash the `features` entry to observe the red run).

- [ ] **Step 3: Write `test-integration.sh`.** Builds the workspace image
  once (`npx -y @devcontainers/cli@latest build --workspace-folder …
  --image-name gca-integration:latest`), then drives **real commits** via
  `docker run` — bind mounts on `devcontainer up` would resolve against the
  outer host, so integration uses `docker run` with a temp spec file:
  `-v "$TMP/spec.conf:/etc/devcontainer/feature/git-commit-attribution/trailer-contract:ro"`.
  Each case is a `docker run --rm [-u …] gca-integration:latest bash -lc '…'`
  that creates a scratch repo and attempts a commit; assertions read exit
  codes, stderr, and `git log`. Cases (spec content per case; write both a
  warn and an enforce variant of the contract into `$TMP`):

```
enforce + compliant 5-trailer block            → commit created
enforce + fabricated #23 block (no Skills:)    → rejected; stderr names 'Skills'
warn    + same fabricated block                → commit created; WARNING printed
enforce + worklog-contribute's current message → rejected
human commit, no trailers                      → created, silently
no spec mounted at all                         → rejected; names the spec path
spec path mounted as a directory (-v tmpdir:…) → rejected; names the spec path
git commit --no-verify with a violating msg    → created (documented bypass)
commit as root (-u root)                       → gate still applies (rejection
                                                 under enforce names the same
                                                 /etc path)
commit from a linked worktree                  → gate applies; repo hooks in
                                                 the main .git still chain
repo with .git/hooks/pre-commit               → still runs with the gate
                                                 installed
GIT_CONFIG_NOSYSTEM=1 + violating msg          → commit created (bypass is
                                                 real; documented)
/usr/local/bin/node symlink                    → exists in image, executable,
                                                 resolves to nvm current
/etc/gitconfig core.hooksPath                  → equals the gate's hooks dir
```

  Also assert once, inside the image: the mounted contract's bytes equal the
  `$TMP` source file — i.e. the mount carries the contract unmodified.

- [ ] **Step 4: Run both suites to green.** These are slow (an image build);
  that is acceptable — they are the proof the design's *Testing* table
  demands. Any fixture that cannot be made to pass is a stop-and-report,
  not a skip.

- [ ] **Step 5: Commit** `Wire the gate into devcontainer.json and prove it
  end-to-end` (+ trailer block, verified).

---

### Task 9: CI workflow (`tests.yml`)

**Files:**
- Create: `.github/workflows/tests.yml`

**Interfaces:**
- Consumes: every suite and npm script above; the pre-existing
  `local-features/*/test/*.sh` suites (agent-skills, codex — enumerate at
  implementation time), which have **never run in CI**.

- [ ] **Step 1: Write `tests.yml`:**

```yaml
name: tests
on:
  push:
    branches: [main]
  pull_request:

jobs:
  validator:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - uses: actions/setup-node@v5
        with:
          node-version: 22
          cache: npm
      - run: npm ci
      - run: npm run typecheck
      - run: npm run lint
      - run: npm test
      # A stale committed bundle fails here; this is what makes the
      # byte-identical-bundle claim enforceable.
      - run: npm run build && git diff --exit-code -- .devcontainer/local-features/git-commit-attribution/dist/

  local-features:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - uses: actions/setup-node@v5
        with:
          node-version: 22
      - name: Run every local-feature test suite
        run: |
          set -euo pipefail
          shopt -s nullglob
          for t in .devcontainer/local-features/*/test/*.sh; do
            case "$t" in
              *test-codex-sandbox.sh) echo "skip (in-container only): $t"; continue ;;
            esac
            echo "== $t"
            bash "$t"
          done
```

  Verify `actions/checkout` and `actions/setup-node` major versions are
  current (`gh api repos/actions/checkout/releases/latest --jq .tag_name`,
  same for setup-node) and adjust if a newer major exists.

- [ ] **Step 2: Push the branch and watch the run**
  (`gh run watch`). The pre-existing suites (agent-skills, codex) have never
  run in CI; if one fails for a CI-environment reason unrelated to this
  work, **stop and report** the exact failure to the orchestrator rather
  than patching another Feature's tests or excluding it silently — that is a
  scoping decision the orchestrator must make.

- [ ] **Step 3: Iterate until all checks pass**, then commit any fixes
  (`Add CI running the validator suite and all local-feature suites`,
  + trailer block, verified).

---

### Task 10: Codex-sandbox probe and design-doc status

**Files:**
- Create: `.devcontainer/local-features/git-commit-attribution/test/test-codex-sandbox.sh`
- Modify: `docs/designs/2026-07-10-git-commit-attribution-design.md`

The design's one open question: whether a `git commit` launched inside
Codex's inner bwrap sandbox sees `/etc/gitconfig`, the hooks directory, and
the read-only spec mount. It cannot be answered from CI (no bwrap
user-namespace setup on the runner) nor from the current running container
(the gate is not installed in it). The probe therefore ships as an
**in-container script** run after the first rebuild, and the design keeps the
question open with a pointer to the probe as its resolution path.

- [ ] **Step 1: Write `test-codex-sandbox.sh`.** Read
  `local-features/codex/NOTES.md`, `install.sh`, and `bin/` first to learn
  the exact sandbox invocation the Feature provides (the bwrap wrapper it
  installs), then write the probe:
  - Guard: exit 0 with a `skip:` message unless both
    `/usr/local/share/git-commit-attribution/hooks` and the Codex sandbox
    wrapper exist (so the script is safe to run anywhere, including CI and
    the current un-rebuilt container).
  - Probe: in a scratch repo, run
    `git commit --allow-empty -m '<violating agent-style message>'`
    **through the sandbox wrapper**, against the live spec at the real
    `/etc` path (the path is fixed and read-only, so no temp spec — the
    rebuilt container's spec is `mode warn`, so the commit succeeds and the
    gate's diagnosis is the observable).
  - Assert: the sandboxed command's stderr contains
    `git-commit-attribution:` (the WARNING diagnosis). That output being
    visible from a sandbox-launched commit is exactly the design's open
    question. Print `PASS: gate visible inside Codex sandbox` or
    `FAIL: gate did not fire inside Codex sandbox`.

- [ ] **Step 2: Update the design document:**
  - Status line →
    `Status: Accepted — merged via hube/devcontainer#38 (2026-07-18). Implementation: docs/implementation-plans/2026-08-03-git-commit-attribution-gate-implementation-plan.md and …-spec-implementation-plan.md.`
  - *The producer* section: append one sentence — the fallback-safety
    refactor merged (`hube/agent-skills#54`, 2026-07-31), so `#9` is
    unblocked and only the `enforce` flip still waits on it.
  - *Open Questions*: keep the Codex-sandbox question open, add the pointer:
    resolved by running `test/test-codex-sandbox.sh` inside the first
    rebuilt container, before the `enforce` flip (tracked in `#51`).
  - Changelog: one new entry dated with the implementation PR.

- [ ] **Step 3: Run** `bash test/test-codex-sandbox.sh` in the current
  container — expect the `skip:` guard exit (gate not installed here), which
  proves the guard works.

- [ ] **Step 4: Commit** `Add the Codex-sandbox probe and update the design
  status` (+ trailer block, verified).

---

## Out of Scope

- **The spec file and `CLAUDE.md` edits in `hube/claude-home`**: the sibling
  spec plan, implemented by a separate agent.
- **`hube/agent-skills#9`** (the `--trailer` producer fix): separate
  repository, separate plan, written against that repo's merged
  fallback-safety design. Now unblocked (`hube/agent-skills#54` merged
  2026-07-31).
- **The `enforce` flip** (`#51` step 4): a host-side spec edit, gated on #9
  and on a clean warn-mode period plus a passing Codex-sandbox probe.
- **Per-repo CI trailer checks** in other repos (deferred in the design;
  range mode + `--spec` exist to make them cheap later).
- **`Subagents:` trailer**: reserved extension point; do not implement.

## Deployment ordering (orchestrator checklist, tracks `hube/devcontainer#51`)

1. Merge the `claude-home` PR (spec plan); `git pull` it on the host at
   `~/.claude`.
2. Merge this repo's PR; rebuild the container.
3. Run `test/test-codex-sandbox.sh` in the rebuilt container; record the
   result on #51 and in the design's Open Questions.
4. Leave `mode warn` until `hube/agent-skills#9` lands (its own plan).
