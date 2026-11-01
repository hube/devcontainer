import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { buildSync } from 'esbuild';
import { mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { spawn } from 'node:child_process';

// Only the parser executable is stubbed. Each runner is a separate process so
// an outer watchdog can terminate its whole task-owned process group.
const dir = mkdtempSync(join(tmpdir(), 'gca-parser-'));
const runner = join(dir, 'runner.cjs');
const stubDir = join(dir, 'bin');
const pidFile = join(dir, 'parser.pid');
const message = 'Bound parser\n\nHarness: Codex\nHarness-Version: test\nModel: test\nSkills: none\nCo-Authored-By: Test <noreply@openai.com>\n';

beforeAll(() => {
  mkdirSync(stubDir);
  writeFileSync(join(stubDir, 'git'), `#!${process.execPath}
const fs = require('node:fs');
fs.writeFileSync(process.env.PARSER_PID_FILE, String(process.pid));
process.stdout.write('parser stdout retained\\n');
process.stderr.write('parser stderr retained\\n');
if (process.env.PARSER_CASE === 'exit') process.exit(23);
process.on('SIGTERM', () => {});
setInterval(() => {}, 1000);
`, { mode: 0o755 });
  buildSync({
    stdin: {
      contents: `
        import { checkMessage } from './src/git-commit-attribution/validate';
        import { parseSpec } from './src/git-commit-attribution/spec';
        const spec = parseSpec('version 1\\nmode ' + process.argv[2] + '\\n' +
          'trailer Harness required\\ntrailer Harness-Version required\\n' +
          'trailer Model required\\ntrailer Skills required\\n' +
          'trailer Co-Authored-By required last\\nagent-author noreply@openai.com\\n');
        if (!spec.ok) throw new Error(spec.problem);
        process.stdout.write(JSON.stringify(checkMessage(${JSON.stringify(message)},
          spec.spec, '/fixture/contract', process.argv[3])));
      `,
      resolveDir: resolve('.'),
    },
    bundle: true, platform: 'node', format: 'cjs', outfile: runner,
  });
});

afterAll(() => rmSync(dir, { recursive: true, force: true }));

async function runParser(mode: string, context: string, failure: 'launch' | 'exit' | 'timeout' | 'normal') {
  const child = spawn(process.execPath, [runner, mode, context], {
    detached: true,
    env: {
      ...process.env,
      PATH: failure === 'normal' ? process.env.PATH : failure === 'launch' ? join(dir, 'absent') : stubDir,
      PARSER_CASE: failure,
      PARSER_PID_FILE: pidFile,
    },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  let stdout = '';
  let stderr = '';
  let watchdogFired = false;
  const watchdog = setTimeout(() => {
    watchdogFired = true;
    if (child.pid) process.kill(-child.pid, 'SIGKILL');
  }, 6_000);
  child.stdout.on('data', (data: Buffer) => { stdout += data.toString(); });
  child.stderr.on('data', (data: Buffer) => { stderr += data.toString(); });
  try {
    const status = await new Promise<number | null>((done, reject) => {
      child.on('error', reject);
      child.on('close', done);
    });
    return { status, stdout, stderr, watchdogFired };
  } finally {
    clearTimeout(watchdog);
  }
}

const cases = [
  ['warn', 'hook'], ['enforce', 'hook'], ['warn', 'range'], ['enforce', 'range'],
];

describe('parser failure boundary', () => {
  it('permits a complete attribution block through real git', async () => {
    const result = await runParser('enforce', 'hook', 'normal');
    expect(result.watchdogFired).toBe(false);
    expect(result.status).toBe(0);
    expect(JSON.parse(result.stdout)).toEqual({ exitCode: 0, stderr: [] });
  });

  it.each(cases)('bounds and diagnoses a hanging child in %s/%s', async (mode, context) => {
    const result = await runParser(mode, context, 'timeout');
    expect(result.watchdogFired, 'outer watchdog fired before validator returned').toBe(false);
    expect(result.status).toBe(0);
    const outcome = JSON.parse(result.stdout) as { exitCode: number; stderr: string[] };
    expect(outcome.exitCode).toBe(1);
    const text = outcome.stderr.join('\n');
    const problem = 'git-commit-attribution: could not validate commit-message trailers: trailer parser timed out after 2000 ms.';
    expect(text).toContain(problem);
    expect(text).toContain('git interpret-trailers --parse stdout:\nparser stdout retained\n');
    expect(text).toContain('git interpret-trailers --parse stderr:\nparser stderr retained\n');
    expect(text.indexOf('parser stderr retained')).toBeLessThan(text.indexOf(problem));
    expect(text).toContain(context === 'hook' ? 'The commit was not created.' : 'This commit could not be checked.');
    expect(text).toContain('use the supported approved execution path');
    expect(text).toContain('keeping the complete attribution block');
    expect(text).not.toContain('--no-verify');
    expect(() => process.kill(Number(readFileSync(pidFile, 'utf8')), 0)).toThrow();
  }, 10_000);

  it.each(cases)('diagnoses an unavailable executable in %s/%s', async (mode, context) => {
    const result = await runParser(mode, context, 'launch');
    expect(result.watchdogFired).toBe(false);
    const outcome = JSON.parse(result.stdout) as { exitCode: number; stderr: string[] };
    expect(outcome.exitCode).toBe(1);
    const text = outcome.stderr.join('\n');
    expect(text).toContain('git-commit-attribution: could not validate commit-message trailers: could not launch git interpret-trailers --parse:');
    expect(text).toContain('Restore git on PATH, then retry validation with the complete attribution block.');
    expect(text).not.toContain('timed out');
  });

  it.each(cases)('relays an unsuccessful parser exit in %s/%s', async (mode, context) => {
    const result = await runParser(mode, context, 'exit');
    expect(result.watchdogFired).toBe(false);
    const outcome = JSON.parse(result.stdout) as { exitCode: number; stderr: string[] };
    expect(outcome.exitCode).toBe(1);
    const text = outcome.stderr.join('\n');
    const problem = 'git-commit-attribution: could not validate commit-message trailers: git interpret-trailers --parse exited with status 23.';
    expect(text).toContain(problem);
    expect(text).toContain('git interpret-trailers --parse stdout:\nparser stdout retained\n');
    expect(text).toContain('git interpret-trailers --parse stderr:\nparser stderr retained\n');
    expect(text.indexOf('parser stderr retained')).toBeLessThan(text.indexOf(problem));
    expect(text).toContain('Resolve the git failure shown above, then retry validation with the complete attribution block.');
    expect(text).not.toContain('timed out');
  });
});
