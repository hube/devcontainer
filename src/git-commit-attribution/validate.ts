import { readFileSync, statSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { parseSpec, type Spec } from './spec';
import { compareSequence, parseTrailers, triggers } from './trailers';

export interface Outcome {
  exitCode: 0 | 1;
  stderr: string[];
}

export type LoadSpecResult = { ok: true; spec: Spec } | { ok: false; outcome: Outcome };

const MISSING_SPEC_CONSEQUENCE = 'every commit is rejected until it exists';
const MISSING_SPEC_REMEDY =
  'mount ~/.claude/git-commit-attribution.conf — a checkout of hube/claude-home — to this path, ' +
  'or bypass once with git commit --no-verify';

/**
 * The contract block shown in every rejection/warning (design, *Failure
 * Behavior*): a fixed teaching template, not derived from the spec's trailer
 * keys, because it addresses a human or agent reader who may never have read
 * CLAUDE.md — including a Codex or ChatGPT agent nobody configured for this
 * repo's live spec.
 */
const CONTRACT_LINES = [
  'Agent-authored commits must end with this contiguous block, Co-Authored-By last:',
  '',
  '  Harness: <harness>',
  '  Harness-Version: <version>',
  '  Model: <model id>',
  "  Skills: <skills used, comma-separated, or 'none'>",
  '  Co-Authored-By: <model display name> <noreply address>',
  '',
];

function rejectSpecPath(specPath: string, problem: string): Outcome {
  return {
    exitCode: 1,
    stderr: [
      `git-commit-attribution: ${problem}.`,
      'The commit was not created.',
      `${MISSING_SPEC_CONSEQUENCE}; ${MISSING_SPEC_REMEDY}.`,
      '',
      `Spec: ${specPath}`,
    ],
  };
}

function rejectSpecProblem(specPath: string, problem: string): Outcome {
  return {
    exitCode: 1,
    stderr: [`git-commit-attribution: ${problem}.`, 'The commit was not created.', '', `Spec: ${specPath}`],
  };
}

/**
 * Reads and parses the spec file, failing closed on any defect: a missing
 * spec, a spec path that is not a regular file, or anything `parseSpec`
 * itself rejects (malformed grammar, unsupported version). The `mode` flag
 * lives inside the spec, so none of these cases can be softened by "warn" —
 * the hook cannot know it is in warn mode until the spec is readable.
 */
export function loadSpec(specPath: string): LoadSpecResult {
  let stat;
  try {
    stat = statSync(specPath);
  } catch (err) {
    const code = (err as NodeJS.ErrnoException).code;
    const problem = code === 'ENOENT' ? `no spec at ${specPath}` : `cannot read spec at ${specPath}: ${(err as Error).message}`;
    return { ok: false, outcome: rejectSpecPath(specPath, problem) };
  }

  if (!stat.isFile()) {
    return { ok: false, outcome: rejectSpecPath(specPath, `spec at ${specPath} is not a file`) };
  }

  let text: string;
  try {
    text = readFileSync(specPath, 'utf8');
  } catch (err) {
    return {
      ok: false,
      outcome: rejectSpecPath(specPath, `cannot read spec at ${specPath}: ${(err as Error).message}`),
    };
  }

  const parsed = parseSpec(text);
  if (!parsed.ok) {
    return { ok: false, outcome: rejectSpecProblem(specPath, parsed.problem) };
  }

  return { ok: true, spec: parsed.spec };
}

/**
 * `'hook'` is the `commit-msg` hook validating a message before the commit
 * object exists — "The commit was not created" is true there. `'range'` is
 * `runRange` re-checking commits `git rev-list` already listed, so the same
 * line would be false: the commit demonstrably exists. Each consequence line
 * below is chosen per context instead of reused across both.
 */
type Context = 'hook' | 'range';

function violationOutcome(problems: string[], specPath: string, context: Context): Outcome {
  const consequence = context === 'range' ? 'This commit violates the trailer contract.' : 'The commit was not created.';
  return {
    exitCode: 1,
    stderr: [
      ...problems.map((p) => `git-commit-attribution: commit message: ${p}.`),
      consequence,
      ...CONTRACT_LINES,
      `Spec: ${specPath}`,
    ],
  };
}

function warningOutcome(problems: string[], specPath: string): Outcome {
  return {
    exitCode: 0,
    stderr: [
      ...problems.map((p) => `git-commit-attribution: WARNING: commit message: ${p}.`),
      'This is a warning only: it will become an error once mode enforce is set.',
      ...CONTRACT_LINES,
      `Spec: ${specPath}`,
    ],
  };
}

/**
 * Full pipeline for one commit message: trigger, parse, compare, then apply
 * the spec's mode. `parseTrailers` shells to real git and throws on a spawn
 * failure or a non-zero exit (see trailers.ts); that is a distinct failure
 * mode from a content violation — the validator itself could not run — so it
 * always fails closed (exit 1) regardless of `mode`.
 */
export function checkMessage(raw: string, spec: Spec, specPath: string, context: Context = 'hook'): Outcome {
  if (!triggers(raw, spec)) {
    return { exitCode: 0, stderr: [] };
  }

  let trailerList;
  try {
    trailerList = parseTrailers(raw);
  } catch (err) {
    const consequence = context === 'range' ? 'This commit could not be checked.' : 'The commit was not created.';
    return {
      exitCode: 1,
      stderr: [
        `git-commit-attribution: could not validate commit-message trailers: ${(err as Error).message}.`,
        consequence,
        'This validator could not run — check that git is installed and on PATH, or bypass once with git commit --no-verify.',
        '',
        `Spec: ${specPath}`,
      ],
    };
  }

  const problems = compareSequence(trailerList, spec);
  if (problems.length === 0) {
    return { exitCode: 0, stderr: [] };
  }

  return spec.mode === 'enforce' ? violationOutcome(problems, specPath, context) : warningOutcome(problems, specPath);
}

/**
 * Entry point for the `commit-msg` hook. The dispatcher now runs the repo's
 * own commit-msg hook before this validator (dispatch.sh), which makes that
 * hook the last writer of `msgfile` before this read — a hook that deletes
 * or otherwise breaks the file is a reachable case, not theoretical. Mirrors
 * loadSpec's own read try/catch so this fails closed with a problem →
 * consequence → remedy message instead of an uncaught exception.
 */
export function runCommitMsg(msgfile: string, specPath: string): Outcome {
  const loaded = loadSpec(specPath);
  if (!loaded.ok) return loaded.outcome;

  let raw: string;
  try {
    raw = readFileSync(msgfile, 'utf8');
  } catch (err) {
    return {
      exitCode: 1,
      stderr: [
        `git-commit-attribution: cannot read the commit message file at ${msgfile}: ${(err as Error).message}.`,
        'The commit was not created.',
        'This validator could not run — check that the commit message file is readable, or bypass once with git commit --no-verify.',
        '',
        `Spec: ${specPath}`,
      ],
    };
  }

  return checkMessage(raw, loaded.spec, specPath);
}

/**
 * Entry point for CI: validates every commit in `range` (via `git rev-list
 * --reverse`) against the same spec and pipeline the hook uses. Each
 * violating commit's stderr lines are prefixed with its abbreviated sha so a
 * multi-commit report stays attributable; blank lines are left unprefixed to
 * keep the block readable. Exits 1 under `mode enforce` if any commit
 * violates; `mode warn` always exits 0 but still prints every diagnosis.
 */
export function runRange(range: string, specPath: string): Outcome {
  const loaded = loadSpec(specPath);
  if (!loaded.ok) return loaded.outcome;

  const revList = spawnSync('git', ['rev-list', '--reverse', range], { encoding: 'utf8' });
  if (revList.error || revList.status !== 0) {
    const detail = revList.error ? revList.error.message : revList.stderr.trim();
    return {
      exitCode: 1,
      stderr: [
        `git-commit-attribution: could not list commits for range '${range}': ${detail}.`,
        'The range check did not run.',
        '',
        `Spec: ${specPath}`,
      ],
    };
  }

  const shas = revList.stdout
    .split('\n')
    .map((s) => s.trim())
    .filter(Boolean);

  let exitCode: 0 | 1 = 0;
  const stderr: string[] = [];

  for (const sha of shas) {
    const shortResult = spawnSync('git', ['rev-parse', '--short', sha], { encoding: 'utf8' });
    const short = shortResult.status === 0 ? shortResult.stdout.trim() : sha.slice(0, 7);

    const logResult = spawnSync('git', ['log', '-1', '--format=%B', sha], { encoding: 'utf8' });
    // A commit git just listed via rev-list but then can't read the message
    // for is an environment failure (corrupted/missing object, git crash),
    // not "no message" — defaulting to '' would make `triggers` see nothing
    // and pass the commit silently. Fail closed unconditionally (exit 1,
    // regardless of `mode`), mirroring the rev-list-failure shape above,
    // rather than routing through `checkMessage`'s mode-dependent handling.
    const outcome =
      logResult.error || logResult.status !== 0
        ? {
            exitCode: 1 as const,
            stderr: [
              `git-commit-attribution: could not read the commit message for ${sha}: ` +
                `${logResult.error ? logResult.error.message : logResult.stderr.trim()}.`,
              'This commit could not be checked.',
              '',
              `Spec: ${specPath}`,
            ],
          }
        : checkMessage(logResult.stdout, loaded.spec, specPath, 'range');

    if (outcome.stderr.length > 0) {
      for (const line of outcome.stderr) {
        stderr.push(line === '' ? '' : `${short}: ${line}`);
      }
      if (outcome.exitCode === 1) {
        exitCode = 1;
      }
    }
  }

  return { exitCode, stderr };
}
