import { spawnSync } from 'node:child_process';
import type { Spec } from './spec';

function escapeRegExp(source: string): string {
  return source.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

/**
 * Reads raw commit-message text (never a parsed-trailer view) so a malformed
 * trailer block — e.g. a prose line immediately above it, which breaks git's
 * own trailer-paragraph heuristic — still trips the gate. Non-last trailer
 * keys fire on any line starting with `<Key>:`. The spec's `last` key (the
 * design's Co-Authored-By slot, but derived from the spec rather than
 * hardcoded) only fires when its line also contains, case-insensitively, one
 * of the spec's agent-author addresses — this is what distinguishes an
 * agent-authored commit from an ordinary human-to-human co-author trailer.
 */
export function triggers(rawMessage: string, spec: Spec): boolean {
  for (const rule of spec.trailers) {
    const linePattern = new RegExp(`^${escapeRegExp(rule.key)}:.*$`, 'gm');
    const matches = rawMessage.match(linePattern);
    if (!matches) continue;

    if (!rule.last) {
      return true;
    }

    for (const line of matches) {
      const lowerLine = line.toLowerCase();
      if (spec.agentAuthors.some((address) => lowerLine.includes(address))) {
        return true;
      }
    }
  }
  return false;
}

export interface Trailer {
  key: string;
  value: string;
}

/**
 * Delegates entirely to `git interpret-trailers --parse` (design, *Validation
 * Flow*): git's definition of a trailer block is the contract's definition,
 * so the hook can never disagree with the `git interpret-trailers --parse`
 * check the contract itself prescribes. This is why a blank line or a prose
 * line inside what looks like a trailer block silently drops trailers —
 * behavior verified directly against git, not reimplemented here.
 *
 * A non-zero git exit throws; the caller (Task 4) converts that into a
 * fail-closed rejection. Failure to launch `git` at all (e.g. missing from
 * `PATH`) is a distinct failure mode from a genuine non-zero exit — the
 * process never ran, so `result.status` is `null` and `result.stdout`/
 * `result.stderr` carry nothing useful, while `result.error` holds the one
 * diagnostic (e.g. `spawn git ENOENT`) that explains why. That case is
 * checked first so its message is never conflated with "exited with status
 * null".
 */
export function parseTrailers(rawMessage: string): Trailer[] {
  const result = spawnSync('git', ['interpret-trailers', '--parse'], {
    input: rawMessage,
    encoding: 'utf8',
  });
  if (result.error) {
    throw new Error(`could not launch git interpret-trailers --parse: ${result.error.message}`);
  }
  if (result.status !== 0) {
    throw new Error(
      `git interpret-trailers --parse exited with status ${result.status}: ${result.stderr}`,
    );
  }

  return result.stdout
    .split('\n')
    .filter((line) => line.length > 0)
    .map((line) => {
      const separatorIndex = line.indexOf(': ');
      if (separatorIndex === -1) {
        return { key: line, value: '' };
      }
      return {
        key: line.slice(0, separatorIndex),
        value: line.slice(separatorIndex + 2),
      };
    });
}

/**
 * Compares a parsed trailer list against the spec's required sequence
 * (design, *Sequence Semantics*). Returns one problem string per defect, or
 * `[]` when compliant.
 *
 * Two passes:
 *
 * 1. Cardinality — every non-`last` required key must appear exactly once in
 *    the *entire* list (not merely once inside a valid run); the `last` key
 *    must appear at least once. A message carrying two attribution blocks —
 *    one valid, one conflicting — must not pass on the strength of the valid
 *    one, so this counts occurrences list-wide. If any required key is
 *    missing entirely, order checks against an absent key would only add
 *    noise, so this stops here and reports the missing/duplicate problems
 *    found so far.
 * 2. Contiguity and order — starting from the first required key in the
 *    list, the remainder must be exactly the non-`last` required keys in
 *    spec order, followed by one or more of the `last` key and nothing else.
 *    Unlisted trailers (`Signed-off-by`, `Change-Id`) are permitted before
 *    that point, never inside or after it.
 */
export function compareSequence(trailers: Trailer[], spec: Spec): string[] {
  const problems: string[] = [];
  const nonLastRules = spec.trailers.filter((rule) => !rule.last);
  const lastRule = spec.trailers[spec.trailers.length - 1];
  const lastKey = lastRule.key;

  let anyMissing = false;
  for (const rule of nonLastRules) {
    const count = trailers.filter((t) => t.key === rule.key).length;
    if (count === 0) {
      problems.push(`missing the required trailer '${rule.key}'`);
      anyMissing = true;
    } else if (count > 1) {
      problems.push(
        `duplicate trailer '${rule.key}': expected exactly one in the message, found ${count}`,
      );
    }
  }
  const lastCount = trailers.filter((t) => t.key === lastKey).length;
  if (lastCount < 1) {
    problems.push(`missing the required trailer '${lastKey}'`);
    anyMissing = true;
  }

  if (anyMissing) {
    return problems;
  }

  const requiredKeys = new Set(spec.trailers.map((rule) => rule.key));
  const firstRequiredIndex = trailers.findIndex((t) => requiredKeys.has(t.key));
  const tail = trailers.slice(firstRequiredIndex);
  const nonLastRunLength = nonLastRules.length;

  const misplacedLastIndex = tail.findIndex(
    (t, i) => t.key === lastKey && i < nonLastRunLength,
  );
  if (misplacedLastIndex !== -1) {
    problems.push(`'${lastKey}' must end the attribution block`);
    return problems;
  }

  for (let i = 0; i < nonLastRunLength; i++) {
    const expectedKey = nonLastRules[i].key;
    const actual = tail[i];
    if (!actual || actual.key !== expectedKey) {
      const found = actual ? `'${actual.key}'` : 'the end of the message';
      problems.push(
        `expected trailer '${expectedKey}' next in the attribution block, but found ${found}`,
      );
      return problems;
    }
  }

  const terminalRun = tail.slice(nonLastRunLength);
  if (terminalRun.length === 0) {
    problems.push(`missing the required trailer '${lastKey}'`);
    return problems;
  }
  for (const t of terminalRun) {
    if (t.key !== lastKey) {
      problems.push(`unexpected trailer '${t.key}' inside the attribution block`);
      return problems;
    }
  }

  return problems;
}
