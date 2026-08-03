import { build } from 'esbuild';
import { chmodSync } from 'node:fs';

const OUTFILE =
  '.devcontainer/local-features/git-commit-attribution/dist/validate';

await build({
  entryPoints: ['src/git-commit-attribution/cli.ts'],
  outfile: OUTFILE,
  bundle: true,
  platform: 'node',
  format: 'cjs',
  target: 'node18',
  // Fixed interpreter path: install.sh guarantees this symlink, so the
  // committed bundle carries no container-specific value (design, *Node*).
  banner: { js: '#!/usr/local/bin/node' },
  legalComments: 'none',
});
chmodSync(OUTFILE, 0o755);
console.log(`built ${OUTFILE}`);
