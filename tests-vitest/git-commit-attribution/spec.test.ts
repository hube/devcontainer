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

  it('parses mode enforce', () => {
    const enforceSpec = LIVE_SPEC.replace('mode         warn', 'mode         enforce');
    const r = parseSpec(enforceSpec);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.spec.mode).toBe('enforce');
  });

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

  it('rejects when last is not on the final trailer record', () => {
    const moved = LIVE_SPEC
      .replace('trailer      Model             required', 'trailer      Model             required last')
      .replace('trailer      Co-Authored-By    required last', 'trailer      Co-Authored-By    required');
    const r = parseSpec(moved);
    expect(r.ok).toBe(false);
  });

  it('rejects a missing mode, a missing version, and an empty spec', () => {
    const missingMode = LIVE_SPEC.replace('mode         warn\n', '');
    const missingVersion = LIVE_SPEC.replace('version      1\n', '');
    expect(parseSpec(missingMode).ok).toBe(false);
    expect(parseSpec(missingVersion).ok).toBe(false);
    expect(parseSpec('').ok).toBe(false);
  });

  it('rejects a duplicate trailer key in the spec', () => {
    const r = parseSpec(LIVE_SPEC + 'trailer      Model             required\n');
    expect(r.ok).toBe(false);
  });
});
