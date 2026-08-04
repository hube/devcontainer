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
