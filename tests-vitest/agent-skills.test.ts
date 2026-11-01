import { spawnSync } from 'node:child_process';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { installTargets } from '../src/agent-skills/install-targets.js';

vi.mock('node:child_process', () => ({ spawnSync: vi.fn() }));

// Only our subprocess arguments and failure handling are under test.
const run = vi.mocked(spawnSync);
const success = { pid: 1, status: 0, signal: null, stdout: '', stderr: '', output: [] };

afterEach(() => vi.restoreAllMocks());

describe('independent installer targets', () => {
  it.each([
    [false, false],
    [true, false],
    [false, true],
    [true, true],
  ])('attempts both when failures are Claude=%s, Codex=%s', (claude, codex) => {
    run.mockReset();
    const errors = vi.spyOn(console, 'error').mockImplementation(() => {});
    for (const failed of [claude, codex]) {
      run.mockReturnValueOnce({
        ...success,
        status: failed ? 1 : 0,
        stdout: failed ? 'installer stdout' : '',
        stderr: failed ? 'installer stderr' : '',
      });
    }
    expect(() => installTargets('/fixture/skills clone')).not.toThrow();
    expect(run.mock.calls).toEqual([
      ['bash', ['/fixture/skills clone/setup.sh', 'claude'], { encoding: 'utf8' }],
      ['bash', ['/fixture/skills clone/setup.sh', 'codex'], { encoding: 'utf8' }],
    ]);
    const messages = errors.mock.calls.map(([message]) => message);
    const expected = [];
    for (const [target, failed] of [['claude', claude], ['codex', codex]]) {
      if (!failed) continue;
      expected.push(
        'agent-skills: setup.sh said: installer stdout\ninstaller stderr',
        `agent-skills: ${target} installation failed (exit 1), so hube-agent skills may not load in ${target}. Follow the installer diagnosis above, then rerun: bash '/fixture/skills clone/setup.sh' ${target}`,
      );
    }
    expect(messages).toEqual(expected);
  });

  it('continues after a failed launch and a terminated installer', () => {
    run.mockReset();
    const errors = vi.spyOn(console, 'error').mockImplementation(() => {});
    run.mockReturnValueOnce({ ...success, status: null, error: new Error('spawn failed') });
    run.mockReturnValueOnce({ ...success, status: null, signal: 'SIGTERM' });
    expect(() => installTargets('/fixture/skills')).not.toThrow();
    expect(run).toHaveBeenCalledTimes(2);
    expect(errors.mock.calls).toEqual([
      ['agent-skills: setup.sh said: spawn failed'],
      [expect.stringContaining('claude installation failed (spawn failed)')],
      ['agent-skills: setup.sh said: no output'],
      [expect.stringContaining('codex installation failed (signal SIGTERM)')],
    ]);
  });
});
