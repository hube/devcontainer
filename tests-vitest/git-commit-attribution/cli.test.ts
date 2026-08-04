import { afterEach, describe, expect, it, vi } from 'vitest';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { DEFAULT_SPEC_PATH, main } from '../../src/git-commit-attribution/cli';

const tmpDirs: string[] = [];
function makeTmpDir(): string {
  const dir = mkdtempSync(join(tmpdir(), 'gca-cli-'));
  tmpDirs.push(dir);
  return dir;
}

afterEach(() => {
  while (tmpDirs.length) {
    const dir = tmpDirs.pop();
    if (dir) rmSync(dir, { recursive: true, force: true });
  }
  vi.restoreAllMocks();
});

// `main` writes diagnostics straight to `process.stderr`, so tests intercept
// the real `write` call rather than injecting a stream — matching how `main`
// is actually invoked from the module tail (no stream parameter to inject).
function captureStderr(): { text: () => string } {
  const chunks: string[] = [];
  vi.spyOn(process.stderr, 'write').mockImplementation((chunk: string | Uint8Array): boolean => {
    chunks.push(typeof chunk === 'string' ? chunk : Buffer.from(chunk).toString('utf8'));
    return true;
  });
  return { text: () => chunks.join('') };
}

describe('main', () => {
  it('commit-msg without --spec falls back to DEFAULT_SPEC_PATH', () => {
    const dir = makeTmpDir();
    const msgfile = join(dir, 'MSG');
    writeFileSync(msgfile, 'subject\n\nbody\n');
    const stderr = captureStderr();

    const exitCode = main(['commit-msg', msgfile]);

    // DEFAULT_SPEC_PATH does not exist on this machine (verified separately),
    // so loadSpec's missing-spec rejection fires and names the compiled-in
    // path — proof that no --spec override reached this call.
    expect(exitCode).toBe(1);
    expect(stderr.text()).toContain(DEFAULT_SPEC_PATH);
  });

  it('commit-msg with --spec uses the override path, not DEFAULT_SPEC_PATH', () => {
    const dir = makeTmpDir();
    const msgfile = join(dir, 'MSG');
    writeFileSync(msgfile, 'subject\n\nbody\n');
    const specPath = join(dir, 'does-not-exist-contract');
    const stderr = captureStderr();

    const exitCode = main(['commit-msg', msgfile, '--spec', specPath]);

    expect(exitCode).toBe(1);
    const text = stderr.text();
    expect(text).toContain(specPath);
    expect(text).not.toContain(DEFAULT_SPEC_PATH);
  });

  it('--range BASE..HEAD --spec PATH runs range mode against PATH', () => {
    const dir = makeTmpDir();
    const specPath = join(dir, 'does-not-exist-contract');
    const stderr = captureStderr();

    const exitCode = main(['--range', 'A..B', '--spec', specPath]);

    expect(exitCode).toBe(1);
    const text = stderr.text();
    expect(text).toContain(specPath);
    expect(text).not.toContain(DEFAULT_SPEC_PATH);
  });

  it('--range BASE..HEAD without --spec falls back to DEFAULT_SPEC_PATH', () => {
    const stderr = captureStderr();

    const exitCode = main(['--range', 'A..B']);

    expect(exitCode).toBe(1);
    expect(stderr.text()).toContain(DEFAULT_SPEC_PATH);
  });

  it('no arguments exits 1 with usage on stderr', () => {
    const stderr = captureStderr();

    const exitCode = main([]);

    expect(exitCode).toBe(1);
    expect(stderr.text().length).toBeGreaterThan(0);
  });

  it('an unrecognized argument exits 1, with usage naming both entry forms', () => {
    const stderr = captureStderr();

    const exitCode = main(['bogus']);

    expect(exitCode).toBe(1);
    const text = stderr.text();
    expect(text).toContain('commit-msg');
    expect(text).toContain('--range');
  });
});
