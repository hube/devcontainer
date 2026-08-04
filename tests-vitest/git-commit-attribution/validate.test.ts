import { afterEach, describe, expect, it, vi } from 'vitest';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import type { SpawnSyncReturns } from 'node:child_process';
import { spawnSync } from 'node:child_process';
import { parseSpec, type Spec } from '../../src/git-commit-attribution/spec';
import { checkMessage, loadSpec, runCommitMsg, runRange } from '../../src/git-commit-attribution/validate';

// `vi.mock` on a Node built-in must be a passthrough by default — ESM module
// namespaces are not configurable, so `vi.spyOn` on 'node:child_process'
// throws ("Cannot redefine property"); this indirection is the standard
// vitest workaround. `failOnLogSha` (set only by the one test that needs it)
// lets a single, targeted `git log` invocation report a git failure while
// every other spawnSync call — in this file and in the modules under test —
// still runs real git. `vi.hoisted` is required because `vi.mock` factories
// run before any module-scope `let` below them would otherwise be assigned.
const { getFailOnLogSha, setFailOnLogSha } = vi.hoisted(() => {
  let target: string | null = null;
  return {
    getFailOnLogSha: () => target,
    setFailOnLogSha: (sha: string | null) => {
      target = sha;
    },
  };
});

vi.mock('node:child_process', async (importOriginal) => {
  const actual = await importOriginal<typeof import('node:child_process')>();
  return {
    ...actual,
    spawnSync: (cmd: string, args?: readonly string[], opts?: unknown) => {
      const argv = args ? [...args] : [];
      const target = getFailOnLogSha();
      if (cmd === 'git' && argv[0] === 'log' && target !== null && argv.includes(target)) {
        return {
          status: 128,
          signal: null,
          error: undefined,
          pid: 0,
          output: [null, '', `fatal: bad object ${target}`],
          stdout: '',
          stderr: `fatal: bad object ${target}`,
        } as SpawnSyncReturns<string>;
      }
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      return actual.spawnSync(cmd as any, argv as any, opts as any);
    },
  };
});

// Byte-identical to spec.test.ts's LIVE_SPEC (and the design doc's *The spec*
// section). Duplicated here per the task-2 brief's resolution, extended to
// this fourth test file: LIVE_SPEC and mustParse are not exported from
// spec.ts, and this test-only duplication avoids touching the other suites.
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

const DEFAULT_SPEC_PATH = '/etc/devcontainer/feature/git-commit-attribution/trailer-contract';

const tmpDirs: string[] = [];
function makeTmpDir(): string {
  const dir = mkdtempSync(join(tmpdir(), 'gca-validate-'));
  tmpDirs.push(dir);
  return dir;
}

afterEach(() => {
  while (tmpDirs.length) {
    const dir = tmpDirs.pop();
    if (dir) rmSync(dir, { recursive: true, force: true });
  }
});

describe('loadSpec', () => {
  it('rejects a missing spec file, naming the path and stating the commit was not created', () => {
    const dir = makeTmpDir();
    const specPath = join(dir, 'trailer-contract');
    const result = loadSpec(specPath);
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.outcome.exitCode).toBe(1);
    const text = result.outcome.stderr.join('\n');
    expect(text).toContain(specPath);
    expect(text).toContain('The commit was not created.');
    expect(text).toContain('no spec at');
  });

  it('rejects a spec path that is a directory, in the same shape ("not a file")', () => {
    const dir = makeTmpDir();
    const result = loadSpec(dir);
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.outcome.exitCode).toBe(1);
    const text = result.outcome.stderr.join('\n');
    expect(text).toContain(dir);
    expect(text).toContain('not a file');
    expect(text).toContain('The commit was not created.');
  });

  it('rejects a malformed spec, naming the offending line', () => {
    const dir = makeTmpDir();
    const specPath = join(dir, 'trailer-contract');
    writeFileSync(specPath, 'version      1\nmode         warn\nbogus-record foo\n');
    const result = loadSpec(specPath);
    expect(result.ok).toBe(false);
    if (result.ok) return;
    expect(result.outcome.exitCode).toBe(1);
    expect(result.outcome.stderr.join('\n')).toContain('bogus-record foo');
  });

  it('rejects an unsupported spec version, naming the remedy', () => {
    const dir = makeTmpDir();
    const specPath = join(dir, 'trailer-contract');
    writeFileSync(specPath, LIVE_SPEC.replace('version      1', 'version      2'));
    const result = loadSpec(specPath);
    expect(result.ok).toBe(false);
    if (result.ok) return;
    const text = result.outcome.stderr.join('\n');
    expect(text).toContain('rebuild the container');
    expect(text).toContain('pin the spec');
  });

  it('loads a well-formed spec', () => {
    const dir = makeTmpDir();
    const specPath = join(dir, 'trailer-contract');
    writeFileSync(specPath, LIVE_SPEC);
    const result = loadSpec(specPath);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.spec.mode).toBe('warn');
  });
});

describe('checkMessage', () => {
  const spec = mustParse(LIVE_SPEC); // mode warn
  const enforceSpec = mustParse(LIVE_SPEC.replace('mode         warn', 'mode         enforce'));

  it('passes silently when the message trips no trigger', () => {
    const outcome = checkMessage('subject\n\nJust a body, nothing agentic.\n', spec, DEFAULT_SPEC_PATH);
    expect(outcome).toEqual({ exitCode: 0, stderr: [] });
  });

  it('passes silently when the message is a compliant block', () => {
    const message =
      'subject\n\n' +
      'Harness: Claude Code\n' +
      'Harness-Version: 2.1.205 (Claude Code)\n' +
      'Model: claude-haiku-4-5-20251001\n' +
      'Skills: none\n' +
      'Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>\n';
    expect(checkMessage(message, spec, DEFAULT_SPEC_PATH)).toEqual({ exitCode: 0, stderr: [] });
  });

  it('rejects a violation under mode enforce, matching the design template exactly', () => {
    const message =
      'Enhance issue\n\n' +
      'Harness: Claude Code\n' +
      'Harness-Version: 2.1.205 (Claude Code)\n' +
      'Model: claude-haiku-4-5-20251001\n' +
      'Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>\n'; // no Skills
    const outcome = checkMessage(message, enforceSpec, DEFAULT_SPEC_PATH);
    expect(outcome.exitCode).toBe(1);
    expect(outcome.stderr.join('\n')).toBe(
      "git-commit-attribution: commit message is missing the required trailer 'Skills'.\n" +
        'The commit was not created.\n' +
        'Agent-authored commits must end with this contiguous block, Co-Authored-By last:\n' +
        '\n' +
        '  Harness: <harness>\n' +
        '  Harness-Version: <version>\n' +
        '  Model: <model id>\n' +
        "  Skills: <skills used, comma-separated, or 'none'>\n" +
        '  Co-Authored-By: <model display name> <noreply address>\n' +
        '\n' +
        `Spec: ${DEFAULT_SPEC_PATH}`,
    );
  });

  it('lists multiple problems on their own lines, with a single contract section', () => {
    const message = 'subject\n\nCo-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>\n'; // missing everything else
    const outcome = checkMessage(message, enforceSpec, DEFAULT_SPEC_PATH);
    expect(outcome.exitCode).toBe(1);
    const lines = outcome.stderr;
    const problemLines = lines.filter((l) => l.startsWith('git-commit-attribution: '));
    expect(problemLines.length).toBeGreaterThan(1);
    expect(lines.filter((l) => l === 'The commit was not created.')).toHaveLength(1);
    expect(lines.filter((l) => l.startsWith('Agent-authored commits must end'))).toHaveLength(1);
    expect(lines.filter((l) => l.startsWith('Spec: '))).toHaveLength(1);
  });

  it('warns instead of rejecting under mode warn, naming the same diagnosis', () => {
    const message =
      'Enhance issue\n\n' +
      'Harness: Claude Code\n' +
      'Harness-Version: 2.1.205 (Claude Code)\n' +
      'Model: claude-haiku-4-5-20251001\n' +
      'Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>\n'; // no Skills
    const outcome = checkMessage(message, spec, DEFAULT_SPEC_PATH); // spec.mode === 'warn'
    expect(outcome.exitCode).toBe(0);
    const text = outcome.stderr.join('\n');
    expect(text).toContain('WARNING');
    expect(text).toContain("missing the required trailer 'Skills'");
    expect(text).toContain('will become an error');
  });

  it('fails closed when the trailer parser cannot run git', () => {
    const message =
      'Enhance issue\n\n' +
      'Harness: Claude Code\n' +
      'Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>\n';
    const savedPath = process.env.PATH;
    try {
      process.env.PATH = '';
      const outcome = checkMessage(message, enforceSpec, DEFAULT_SPEC_PATH);
      expect(outcome.exitCode).toBe(1);
      expect(outcome.stderr.join('\n')).toContain('git-commit-attribution: ');
    } finally {
      process.env.PATH = savedPath;
    }
  });
});

describe('runCommitMsg', () => {
  it('reads the message file and validates it', () => {
    const dir = makeTmpDir();
    const specPath = join(dir, 'trailer-contract');
    writeFileSync(specPath, LIVE_SPEC);
    const msgfile = join(dir, 'COMMIT_EDITMSG');
    writeFileSync(msgfile, 'subject\n\nJust a body.\n');
    expect(runCommitMsg(msgfile, specPath)).toEqual({ exitCode: 0, stderr: [] });
  });

  it('fails closed when the spec is missing', () => {
    const dir = makeTmpDir();
    const specPath = join(dir, 'trailer-contract'); // never written
    const msgfile = join(dir, 'COMMIT_EDITMSG');
    writeFileSync(msgfile, 'subject\n\nJust a body.\n');
    const outcome = runCommitMsg(msgfile, specPath);
    expect(outcome.exitCode).toBe(1);
  });
});

describe('runRange', () => {
  // System-scope git config installs this Feature's own commit-msg gate
  // (core.hooksPath -> the live validator) once the branch is consumed in a
  // rebuilt container. Every scratch-repo git invocation below creates or
  // reads commits, so all of them isolate against that live gate the same
  // way the security-guidance plugin hook does (see NOTES.md's Bypasses
  // section) — otherwise a future enforce-mode spec would reject the
  // `violatingMessage` fixture commit and break this suite.
  const ISOLATED_GIT_ENV = { ...process.env, GIT_CONFIG_NOSYSTEM: '1', GIT_CONFIG_GLOBAL: '/dev/null' };

  function initRepo(dir: string): void {
    spawnSync('git', ['init', '--quiet'], { cwd: dir, env: ISOLATED_GIT_ENV });
    spawnSync('git', ['config', 'user.name', 'Test User'], { cwd: dir, env: ISOLATED_GIT_ENV });
    spawnSync('git', ['config', 'user.email', 'test@example.com'], { cwd: dir, env: ISOLATED_GIT_ENV });
  }

  function runInRepo<T>(dir: string, fn: () => T): T {
    const savedCwd = process.cwd();
    process.chdir(dir);
    try {
      return fn();
    } finally {
      process.chdir(savedCwd);
    }
  }

  const compliantMessage =
    'Compliant commit\n\n' +
    'Harness: Claude Code\n' +
    'Harness-Version: 2.1.205 (Claude Code)\n' +
    'Model: claude-haiku-4-5-20251001\n' +
    'Skills: none\n' +
    'Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>\n';

  const violatingMessage =
    'Violating commit\n\n' +
    'Harness: Claude Code\n' +
    'Harness-Version: 2.1.205 (Claude Code)\n' +
    'Model: claude-haiku-4-5-20251001\n' +
    'Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>\n'; // no Skills

  function buildScratchRepo(): { dir: string; violatingShort: string } {
    const dir = makeTmpDir();
    initRepo(dir);
    // A base commit before the two under test, so 'HEAD~2..HEAD' (per the
    // task brief's exact invocation) has a valid exclusive lower bound.
    spawnSync('git', ['commit', '--allow-empty', '-m', 'Base commit\n'], { cwd: dir, env: ISOLATED_GIT_ENV });
    spawnSync('git', ['commit', '--allow-empty', '-m', compliantMessage], { cwd: dir, env: ISOLATED_GIT_ENV });
    spawnSync('git', ['commit', '--allow-empty', '-m', violatingMessage], { cwd: dir, env: ISOLATED_GIT_ENV });
    const shortResult = spawnSync('git', ['rev-parse', '--short', 'HEAD'], {
      cwd: dir,
      encoding: 'utf8',
      env: ISOLATED_GIT_ENV,
    });
    return { dir, violatingShort: shortResult.stdout.trim() };
  }

  it('reports the violating commit and exits 1 under mode enforce', () => {
    const { dir, violatingShort } = buildScratchRepo();
    const specPath = join(dir, 'trailer-contract');
    writeFileSync(specPath, LIVE_SPEC.replace('mode         warn', 'mode         enforce'));

    const outcome = runInRepo(dir, () => runRange('HEAD~2..HEAD', specPath));
    expect(outcome.exitCode).toBe(1);
    const text = outcome.stderr.join('\n');
    expect(text).toContain(violatingShort);
    expect(text).toContain("missing the required trailer 'Skills'");
  });

  it('reports the same diagnosis but exits 0 under mode warn', () => {
    const { dir, violatingShort } = buildScratchRepo();
    const specPath = join(dir, 'trailer-contract');
    writeFileSync(specPath, LIVE_SPEC); // mode warn

    const outcome = runInRepo(dir, () => runRange('HEAD~2..HEAD', specPath));
    expect(outcome.exitCode).toBe(0);
    const text = outcome.stderr.join('\n');
    expect(text).toContain(violatingShort);
    expect(text).toContain('WARNING');
  });

  it('fails closed, exit 1, when git log cannot read a listed commit message, even under mode warn', () => {
    const { dir, violatingShort } = buildScratchRepo();
    const specPath = join(dir, 'trailer-contract');
    writeFileSync(specPath, LIVE_SPEC); // mode warn — this must still reject, not silently pass

    // A real git repo can't be corrupted so that `rev-list` lists a sha but
    // `git log --format=%B` then fails to read that same sha — both read the
    // identical object (a commit object stores its parent pointers and its
    // message together), so whatever makes one unreadable makes both fail.
    // The failure is instead injected via the module-level spawnSync mock
    // (see the top of this file): `setFailOnLogSha` targets only the `log`
    // invocation for the violating commit's full sha, which is made to fail
    // the way a corrupted/missing object would (non-zero exit, `fatal:`
    // stderr). rev-list, rev-parse --short, and the other commit's `log`
    // call all still run through real git.
    const fullShaResult = spawnSync('git', ['rev-parse', 'HEAD'], {
      cwd: dir,
      encoding: 'utf8',
      env: ISOLATED_GIT_ENV,
    });
    const violatingFullSha = fullShaResult.stdout.trim();

    setFailOnLogSha(violatingFullSha);
    try {
      const outcome = runInRepo(dir, () => runRange('HEAD~2..HEAD', specPath));
      expect(outcome.exitCode).toBe(1);
      const text = outcome.stderr.join('\n');
      expect(text).toContain(violatingShort);
      expect(text).toContain('bad object');
    } finally {
      setFailOnLogSha(null);
    }
  });
});
