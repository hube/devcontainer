import { describe, expect, it } from 'vitest';
import { parseSpec, type Spec } from '../../src/git-commit-attribution/spec';
import { compareSequence, parseTrailers } from '../../src/git-commit-attribution/trailers';

// Byte-identical to spec.test.ts's LIVE_SPEC (and the design doc's *The spec*
// section). Duplicated here per the task-2 brief's resolution, extended to
// this third test file: LIVE_SPEC and mustParse are not exported from
// spec.ts, and this test-only duplication avoids touching the other two
// suites.
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

describe('parseTrailers', () => {
  it('parses a well-formed trailer block via real git', () => {
    const message =
      'Enhance issue\n\n' +
      'Harness: Claude Code\n' +
      'Harness-Version: 2.1.205 (Claude Code)\n' +
      'Model: claude-haiku-4-5-20251001\n' +
      'Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>\n';
    expect(parseTrailers(message)).toEqual([
      { key: 'Harness', value: 'Claude Code' },
      { key: 'Harness-Version', value: '2.1.205 (Claude Code)' },
      { key: 'Model', value: 'claude-haiku-4-5-20251001' },
      { key: 'Co-Authored-By', value: 'Claude Haiku 4.5 <noreply@anthropic.com>' },
    ]);
  });

  it('returns only the trailers after a blank line that splits the block', () => {
    // Verified behavior (design doc): a blank line inside what looks like a
    // trailer block makes git return only the paragraph after it.
    const message =
      'subject\n\n' +
      'Harness: Claude Code\n' +
      'Harness-Version: 2.1.205 (Claude Code)\n' +
      '\n' +
      'Model: claude-haiku-4-5-20251001\n' +
      'Skills: none\n' +
      'Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>\n';
    expect(parseTrailers(message)).toEqual([
      { key: 'Model', value: 'claude-haiku-4-5-20251001' },
      { key: 'Skills', value: 'none' },
      { key: 'Co-Authored-By', value: 'Claude Haiku 4.5 <noreply@anthropic.com>' },
    ]);
  });

  it('returns nothing when a prose line sits inside the block', () => {
    // Verified behavior (design doc): a non-trailer line inside the block
    // breaks git's trailer-paragraph heuristic entirely.
    const message =
      'subject\n\n' +
      'Harness: Claude Code\n' +
      'Harness-Version: 2.1.205 (Claude Code)\n' +
      'Some prose.\n' +
      'Model: claude-haiku-4-5-20251001\n' +
      'Skills: none\n' +
      'Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>\n';
    expect(parseTrailers(message)).toEqual([]);
  });

  it('returns an empty array for a message with no trailers at all', () => {
    expect(parseTrailers('subject\n\nJust a plain body, no trailers here.\n')).toEqual([]);
  });

  it('reports a distinct message when git itself cannot be launched', () => {
    // spawnSync's ENOENT path (git missing from PATH) sets result.error and
    // leaves result.status null / result.stdout+stderr null — a materially
    // different failure than a genuine non-zero exit, which must not be
    // described as if the process "exited".
    const savedPath = process.env.PATH;
    try {
      process.env.PATH = '';
      expect(() => parseTrailers('subject\n\nHarness: Claude Code\n')).toThrowError(
        /could not launch .*git.*: .*ENOENT/i,
      );
    } finally {
      process.env.PATH = savedPath;
    }
  });
});

describe('compareSequence', () => {
  const spec = mustParse(LIVE_SPEC);

  function problemsFor(message: string): string[] {
    return compareSequence(parseTrailers(message), spec);
  }

  it("rejects #23's fabricated block (no Skills:)", () => {
    const message =
      'Enhance issue\n\n' +
      'Harness: Claude Code\n' +
      'Harness-Version: 2.1.205 (Claude Code)\n' +
      'Model: claude-haiku-4-5-20251001\n' +
      'Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>\n';
    expect(problemsFor(message)).not.toEqual([]);
  });

  it("passes #23's amended block (adds Skills: before Co-Authored-By)", () => {
    const message =
      'Enhance issue\n\n' +
      'Harness: Claude Code\n' +
      'Harness-Version: 2.1.205 (Claude Code)\n' +
      'Model: claude-haiku-4-5-20251001\n' +
      'Skills: superpowers:subagent-driven-development\n' +
      'Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>\n';
    expect(problemsFor(message)).toEqual([]);
  });

  it('rejects a Codex-style block with Model: gpt-5 and no Skills:', () => {
    const message =
      'Fix bug\n\n' +
      'Harness: Codex CLI\n' +
      'Harness-Version: 0.144.5\n' +
      'Model: gpt-5\n' +
      'Co-Authored-By: GPT-5 <noreply@openai.com>\n';
    expect(problemsFor(message)).not.toEqual([]);
  });

  it('passes the same Codex block with "Skills: none" inserted', () => {
    const message =
      'Fix bug\n\n' +
      'Harness: Codex CLI\n' +
      'Harness-Version: 0.144.5\n' +
      'Model: gpt-5\n' +
      'Skills: none\n' +
      'Co-Authored-By: GPT-5 <noreply@openai.com>\n';
    expect(problemsFor(message)).toEqual([]);
  });

  it('rejects a blank line splitting the block (git parses only the tail)', () => {
    const message =
      'subject\n\n' +
      'Harness: Claude Code\n' +
      'Harness-Version: 2.1.205 (Claude Code)\n' +
      '\n' +
      'Model: claude-haiku-4-5-20251001\n' +
      'Skills: none\n' +
      'Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>\n';
    expect(problemsFor(message)).not.toEqual([]);
  });

  it('rejects a prose line inside the block (git parses zero trailers)', () => {
    const message =
      'subject\n\n' +
      'Harness: Claude Code\n' +
      'Harness-Version: 2.1.205 (Claude Code)\n' +
      'Some prose.\n' +
      'Model: claude-haiku-4-5-20251001\n' +
      'Skills: none\n' +
      'Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>\n';
    expect(problemsFor(message)).not.toEqual([]);
  });

  it('rejects Co-Authored-By not last (Skills after it)', () => {
    const message =
      'subject\n\n' +
      'Harness: Claude Code\n' +
      'Harness-Version: 2.1.205 (Claude Code)\n' +
      'Model: claude-haiku-4-5-20251001\n' +
      'Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>\n' +
      'Skills: none\n';
    expect(problemsFor(message)).not.toEqual([]);
  });

  it('passes repeated Co-Authored-By ending the block (two harness co-authors)', () => {
    const message =
      'subject\n\n' +
      'Harness: Claude Code\n' +
      'Harness-Version: 2.1.205 (Claude Code)\n' +
      'Model: claude-haiku-4-5-20251001\n' +
      'Skills: none\n' +
      'Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>\n' +
      'Co-Authored-By: GPT-5 <noreply@openai.com>\n';
    expect(problemsFor(message)).toEqual([]);
  });

  it('rejects a duplicate Model: elsewhere in the trailer list', () => {
    const message =
      'subject\n\n' +
      'Model: duplicate-elsewhere\n' +
      'Harness: Claude Code\n' +
      'Harness-Version: 2.1.205 (Claude Code)\n' +
      'Model: claude-haiku-4-5-20251001\n' +
      'Skills: none\n' +
      'Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>\n';
    // The specific diagnosis, not merely "some problem": the contiguity pass
    // rejects this message on its own, so a weaker assertion stays green even
    // with the exactly-once cardinality check disabled.
    expect(problemsFor(message)).toContain(
      "duplicate trailer 'Model': expected exactly one in the message, found 2",
    );
  });

  it('rejects two complete attribution blocks, one valid', () => {
    const message =
      'subject\n\n' +
      'Harness: Claude Code\n' +
      'Harness-Version: 2.1.205 (Claude Code)\n' +
      'Model: claude-haiku-4-5-20251001\n' +
      'Skills: none\n' +
      'Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>\n' +
      'Harness: Codex CLI\n' +
      'Harness-Version: 0.144.5\n' +
      'Model: gpt-5\n' +
      'Skills: none\n' +
      'Co-Authored-By: GPT-5 <noreply@openai.com>\n';
    expect(problemsFor(message)).toContain(
      "duplicate trailer 'Model': expected exactly one in the message, found 2",
    );
  });

  it('passes Signed-off-by before the block', () => {
    const message =
      'subject\n\n' +
      'Signed-off-by: Alex Doe <alex@example.com>\n' +
      'Harness: Claude Code\n' +
      'Harness-Version: 2.1.205 (Claude Code)\n' +
      'Model: claude-haiku-4-5-20251001\n' +
      'Skills: none\n' +
      'Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>\n';
    expect(problemsFor(message)).toEqual([]);
  });

  it('rejects Signed-off-by after Co-Authored-By (what git commit --signoff produces)', () => {
    const message =
      'subject\n\n' +
      'Harness: Claude Code\n' +
      'Harness-Version: 2.1.205 (Claude Code)\n' +
      'Model: claude-haiku-4-5-20251001\n' +
      'Skills: none\n' +
      'Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>\n' +
      'Signed-off-by: Claude Haiku 4.5 <noreply@anthropic.com>\n';
    expect(problemsFor(message)).not.toEqual([]);
  });
});
