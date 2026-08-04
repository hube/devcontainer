import { afterEach, describe, expect, it, vi } from 'vitest';
import { existsSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { DEFAULT_SPEC_PATH, main } from '../../src/git-commit-attribution/cli';

// Whether the live spec happens to be mounted at the compiled-in path in
// *this* environment. On a plain checkout it is not, so the missing-spec
// assertions below run for real. Inside a rebuilt consumer container the
// devcontainer.json mount puts a real (warn-mode) spec at exactly this path,
// so loadSpec would succeed instead of failing — those specific assertions
// are skipped rather than asserting a false environmental premise; the
// missing-spec fail-closed behavior itself stays covered by loadSpec's own
// unit tests in validate.test.ts regardless of which environment this runs in.
const defaultSpecExists = existsSync(DEFAULT_SPEC_PATH);
const skipIfDefaultSpecExists = (title: string): string =>
  defaultSpecExists
    ? `${title} (skipped: a spec is mounted at ${DEFAULT_SPEC_PATH} in this environment)`
    : title;

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
  it.skipIf(defaultSpecExists)(
    skipIfDefaultSpecExists('commit-msg without --spec falls back to DEFAULT_SPEC_PATH'),
    () => {
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
    },
  );

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

  // Same environmental assumption as the commit-msg case above (a rebuilt
  // container mounts a real spec at DEFAULT_SPEC_PATH), so it gets the same
  // skip treatment.
  it.skipIf(defaultSpecExists)(
    skipIfDefaultSpecExists('--range BASE..HEAD without --spec falls back to DEFAULT_SPEC_PATH'),
    () => {
      const stderr = captureStderr();

      const exitCode = main(['--range', 'A..B']);

      expect(exitCode).toBe(1);
      expect(stderr.text()).toContain(DEFAULT_SPEC_PATH);
    },
  );

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
