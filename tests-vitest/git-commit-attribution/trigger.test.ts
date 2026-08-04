import { describe, expect, it } from 'vitest';
import { parseSpec, type Spec } from '../../src/git-commit-attribution/spec';
import { triggers } from '../../src/git-commit-attribution/trailers';

// Byte-identical to spec.test.ts's LIVE_SPEC (and the design doc's *The spec*
// section). Duplicated here per the task-2 brief's resolution: LIVE_SPEC and
// mustParse are not exported from spec.ts, and this test-only duplication
// avoids touching spec.test.ts.
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

function mustParse(text: string): Spec {
  const r = parseSpec(text);
  if (!r.ok) throw new Error(r.problem);
  return r.spec;
}

describe('triggers', () => {
  const spec = mustParse(LIVE_SPEC);

  it('fires on a well-formed agent block', () => {
    const message = [
      'Add feature X',
      '',
      'Harness: Claude Code',
      'Harness-Version: 2.1.221 (Claude Code)',
      'Model: claude-sonnet-5',
      'Skills: superpowers:subagent-driven-development',
      'Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>',
    ].join('\n');
    expect(triggers(message, spec)).toBe(true);
  });

  it('fires on a malformed block (prose line above it)', () => {
    // This is the load-bearing case: a parsed-trailer view would see nothing
    // (the prose line breaks git's trailer-paragraph heuristic), but raw text
    // still matches ^Harness:.
    const message = [
      'subject',
      '',
      'Some prose.',
      'Harness: Claude Code',
      'Harness-Version: 2.1.221 (Claude Code)',
      'Model: claude-sonnet-5',
      'Skills: superpowers:subagent-driven-development',
      'Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>',
    ].join('\n');
    expect(triggers(message, spec)).toBe(true);
  });

  it('fires on Co-Authored-By with an agent address only', () => {
    // worklog-contribute's real current output (src/worklog/git.ts): only a
    // Co-Authored-By trailer, no other agent-block lines.
    const message = 'subject\n\nCo-Authored-By: claude-opus-4-8 <noreply@anthropic.com>';
    expect(triggers(message, spec)).toBe(true);
  });

  it('fires on an agent-author address that differs in case from the spec', () => {
    // The design requires case-insensitive matching; spec.agentAuthors is
    // lowercased by parseSpec, but the commit-message address need not be.
    const message = 'subject\n\nCo-Authored-By: Claude Sonnet 5 <NOREPLY@ANTHROPIC.COM>';
    expect(triggers(message, spec)).toBe(true);
  });

  it('does not fire on human-to-human Co-Authored-By', () => {
    const message = 'subject\n\nCo-Authored-By: Alex Doe <alex@example.com>';
    expect(triggers(message, spec)).toBe(false);
  });

  it('does not fire on a message with no trailers at all', () => {
    const message = 'subject\n\nJust a plain commit message body, no trailers here.';
    expect(triggers(message, spec)).toBe(false);
  });

  it('does not fire on "Harness:" mid-line (not at line start)', () => {
    const message =
      'subject\n\nThis paragraph mentions Harness: Claude Code mid-sentence, not at line start.';
    expect(triggers(message, spec)).toBe(false);
  });

  it('is generated from the spec: a key added to the spec trips it', () => {
    const specWithSubagents = mustParse(
      LIVE_SPEC.replace(
        'trailer      Co-Authored-By    required last',
        'trailer      Subagents         required\ntrailer      Co-Authored-By    required last',
      ),
    );
    const message = 'subject\n\nSubagents: x';
    expect(triggers(message, specWithSubagents)).toBe(true);
  });
});
