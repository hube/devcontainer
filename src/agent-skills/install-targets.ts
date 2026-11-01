import { spawnSync } from 'node:child_process';
import { join } from 'node:path';

export function installTargets(cloneDir: string): void {
  const installer = join(cloneDir, 'setup.sh');
  for (const target of ['claude', 'codex']) {
    const result = spawnSync('bash', [installer, target], { encoding: 'utf8' });
    if (result.status === 0 && !result.error) continue;

    const output = [result.stdout, result.stderr, result.error?.message]
      .filter(Boolean)
      .join('\n');
    console.error(`agent-skills: setup.sh said: ${output || 'no output'}`);
    const outcome = result.error
      ? result.error.message
      : result.signal
        ? `signal ${result.signal}`
        : `exit ${result.status}`;
    const quotedInstaller = `'${installer.replaceAll("'", "'\\''")}'`;
    console.error(
      `agent-skills: ${target} installation failed (${outcome}), so hube-agent skills may not load in ${target}. Follow the installer diagnosis above, then rerun: bash ${quotedInstaller} ${target}`,
    );
  }
}
