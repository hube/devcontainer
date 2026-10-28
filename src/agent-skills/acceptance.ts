import { strict as assert } from 'node:assert';
import { spawnSync } from 'node:child_process';
import {
  appendFileSync, cpSync, existsSync, lstatSync, mkdirSync, mkdtempSync,
  readFileSync, realpathSync, writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const repository = resolve(dirname(fileURLToPath(import.meta.url)), '..');
let evidence: string | undefined;

function run(args: string[], env: NodeJS.ProcessEnv = process.env): string {
  const result = spawnSync(args[0], args.slice(1), {
    env, encoding: 'utf8', timeout: 60_000, maxBuffer: 16 * 1024 * 1024,
  });
  const record = `${JSON.stringify(args)}\nstdout:\n${result.stdout || ''}\nstderr:\n${result.stderr || ''}\nstatus=${result.status}, signal=${result.signal}, error=${result.error?.message || ''}\n`;
  appendFileSync(join(evidence!, 'commands.log'), record);
  if (result.status !== 0 || result.error) {
    console.error(record);
    throw new Error(`${args[0]} failed; see its captured output above`);
  }
  return result.stdout;
}

function check(condition: unknown, message: string): asserts condition {
  assert(condition, message);
}

function accept(source: string, revision: string): void {
  evidence = realpathSync(mkdtempSync(join(tmpdir(), 'skills-acceptance-')));
  console.log(`Evidence: ${evidence}`);
  const remote = join(evidence, 'input.git');
  const preflightHome = join(evidence, 'preflight-home');
  mkdirSync(preflightHome);
  const preflightEnv = {
    ...process.env, HOME: preflightHome, CODEX_HOME: join(preflightHome, '.codex'),
    CLAUDE_CONFIG_DIR: join(preflightHome, '.claude'),
  };
  const problems: string[] = [];
  for (const args of [['node', '--version'], ['claude', '--version'],
    ['codex', '--version'], ['git', '--version'], ['ssh-add', '-l']]) {
    try { run(args, preflightEnv); }
    catch (error) { problems.push(error instanceof Error ? error.message : String(error)); }
  }
  check(problems.length === 0, problems.join('; '));
  run(['git', 'clone', '--bare', '--no-hardlinks', '--', source, remote]);
  const pin = run(['git', '--git-dir', remote, 'rev-parse', '--verify', '--end-of-options', `${revision}^{commit}`]).trim();
  run(['git', '--git-dir', remote, 'symbolic-ref', 'HEAD', 'refs/heads/acceptance-input']);
  run(['git', '--git-dir', remote, 'update-ref', 'refs/heads/acceptance-input', pin]);
  console.log(`Installer commit: ${pin}`);
  appendFileSync(join(evidence, 'commands.log'), `Installer commit: ${pin}\n`);

  for (const label of ['fresh', 'existing', 'claude-conflict', 'codex-conflict']) {
    const consumer = join(evidence, label);
    const home = join(consumer, 'home');
    const clone = join(consumer, 'skills');
    for (const path of ['.claude', '.codex', '.config/devcontainer-feature']) {
      mkdirSync(join(home, path), { recursive: true });
    }
    const env = {
      ...process.env, HOME: home, CODEX_HOME: join(home, '.codex'),
      CLAUDE_CONFIG_DIR: join(home, '.claude'),
    };
    const files = {
      '.claude/settings.json': '{"protectedFixture":"unrelated Claude state"}\n',
      '.codex/auth.json': '{"OPENAI_API_KEY":"synthetic-not-a-real-key"}\n',
      '.codex/history.jsonl': '{"session_id":"synthetic","text":"protected history"}\n',
    };
    for (const [path, bytes] of Object.entries(files)) writeFileSync(join(home, path), bytes);
    const config = '# unrelated configuration\nmodel = "gpt-6.1-sol"\n[profiles.keep]\nmodel = "gpt-6-sol"\n';
    const configPath = join(home, '.codex/config.toml');
    writeFileSync(configPath, config);
    const preserved = (): boolean => Object.entries(files).every(([path, bytes]) =>
      readFileSync(join(home, path), 'utf8') === bytes)
      && readFileSync(configPath, 'utf8').startsWith(config);
    appendFileSync(join(home, '.claude/settings.json'), 'altered');
    check(!preserved(), 'protected-state comparator accepted an altered file');
    writeFileSync(join(home, '.claude/settings.json'), files['.claude/settings.json']);
    check(preserved(), 'protected-state comparator rejected restored bytes');
    appendFileSync(join(evidence, 'commands.log'), `${label}: altered/restored comparator control fired\n`);

    cpSync(join(repository, '.devcontainer/local-features/agent-skills/bin'), join(home, 'bin'), { recursive: true });
    const options = join(home, '.config/devcontainer-feature/agent-skills.env');
    const quote = (value: string): string => `'${value.replaceAll("'", "'\\''")}'`;
    writeFileSync(options, `AGENT_SKILLS_REPO=${quote(remote)}\nAGENT_SKILLS_CLONE_DIR=${quote(clone)}\n`);
    for (const binary of ['node', 'claude', 'codex']) {
      const version = run([binary, '--version'], env).trim();
      console.log(`${label}: ${binary}: ${version}`);
    }
    const hook = join(home, 'bin/devcontainer-feature/agent-skills/postStartScript.sh');
    if (label !== 'fresh') run(['git', 'clone', '--quiet', remote, clone], env);
    if (label === 'existing') {
      for (const target of ['claude', 'codex']) run(['bash', join(clone, 'setup.sh'), target], env);
    }
    const conflict = join(home, '.claude/skills/hube-agent');
    const other = join(consumer, 'other-marketplace');
    if (label === 'claude-conflict') {
      mkdirSync(dirname(conflict), { recursive: true });
      writeFileSync(conflict, 'user-owned conflict\n');
    }
    if (label === 'codex-conflict') {
      run(['git', 'clone', '--quiet', remote, other], env);
      run(['codex', 'plugin', 'marketplace', 'add', other], env);
    }
    const conflictConfig = readFileSync(configPath, 'utf8');
    const readback = (): void => {
      check(run(['git', '-C', clone, 'rev-parse', 'HEAD'], env).trim() === pin, `${label}: clone HEAD changed`);
      if (label === 'claude-conflict') {
        check(readFileSync(conflict, 'utf8') === 'user-owned conflict\n', 'Claude conflict bytes changed');
      } else {
        check(lstatSync(conflict).isSymbolicLink() && realpathSync(conflict) === clone, 'Claude link is not installed at the expected clone');
      }
      const marketplaces = JSON.parse(run(['codex', 'plugin', 'marketplace', 'list', '--json'], env));
      const expectedRoot = label === 'codex-conflict' ? other : clone;
      check(marketplaces.marketplaces.some((entry: { name: string; root: string }) =>
        entry.name === 'hube-agent' && entry.root === expectedRoot), 'Codex marketplace root differs');
      const plugins = JSON.parse(run(['codex', 'plugin', 'list', '--json'], env));
      if (label === 'codex-conflict') {
        check(readFileSync(configPath, 'utf8') === conflictConfig, 'Codex conflict configuration changed');
      } else {
        check(plugins.installed.some((entry: {
          pluginId: string; installed: boolean; enabled: boolean; source: { path: string };
        }) => entry.pluginId === 'hube-agent@hube-agent' && entry.installed && entry.enabled
          && entry.source.path === join(clone, '.codex-payload')), 'Codex plugin is not installed from the expected payload');
      }
      check(preserved(), `${label}: unrelated protected state changed`);
    };
    if (label === 'existing') {
      readback();
      console.log('PASS existing seed: both installations read back before startup');
    }
    const attempts = label === 'fresh' || label === 'existing' ? 2 : 1;
    for (let attempt = 1; attempt <= attempts; attempt++) {
      // Preserve both streams even though a successful hook discards installer chatter.
      const result = spawnSync(hook, [], { env, encoding: 'utf8', timeout: 60_000 });
      appendFileSync(join(evidence, 'commands.log'), `${label}: hook attempt ${attempt}\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}\nstatus=${result.status}, error=${result.error?.message || ''}\n`);
      if (result.status !== 0 || result.error) console.error(result.stdout, result.stderr, result.error);
      check(result.status === 0 && !result.error, `${label}: hook did not return zero`);
      const target = label === 'claude-conflict' ? 'claude' : 'codex';
      if (label.endsWith('conflict')) {
        check(result.stderr.includes(`agent-skills: ${target} installation failed`)
          && result.stderr.includes('setup.sh said:')
          && result.stderr.includes('conflicting user-owned'), `${label}: missing caller conflict diagnostic`);
      } else {
        check(!result.stderr.includes('installation failed'), `${label}: installation failed`);
      }
      readback();
      console.log(`PASS ${label} attempt ${attempt}: installed-state and preservation readback`);
    }
  }
}

try {
  if (!process.argv[2] || process.argv.length > 4) {
    throw new Error('supply one maintained installer Git URL or local path, plus an optional revision');
  }
  const source = process.argv[2];
  const revision = process.argv[3] || 'HEAD';
  check(existsSync(join(repository, '.devcontainer/local-features/agent-skills/bin')), 'run the committed acceptance bundle from this repository');
  accept(source, revision);
  console.log('PASS: actual installer acceptance; image rebuild and running-session reload were not exercised.');
} catch (error) {
  console.error(`Problem: ${error instanceof Error ? error.message : String(error)}.`);
  console.error('Consequence: installed-state acceptance is incomplete; no success is claimed.');
  console.error(`Remedy: repair the named input or prerequisite and rerun node scripts/accept-agent-skills.mjs <Git source> [revision]. Evidence is retained${evidence ? ` at ${evidence}` : ' only after temporary-root creation succeeds'}.`);
  process.exitCode = 1;
}
