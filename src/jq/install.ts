import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { chmodSync, mkdirSync, mkdtempSync, renameSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

export const VERSION = '1.8.2';
export const DESTINATION = '/usr/local/bin/jq';

export function selectArtifact(architecture: string) {
  if (architecture !== 'arm64') {
    throw new Error(`unsupported architecture ${architecture}; the published target is linux/arm64`);
  }
  return {
    name: 'jq-linux-arm64',
    url: `https://github.com/jqlang/jq/releases/download/jq-${VERSION}/jq-linux-arm64`,
    sha256: '8b85c817833814ddca00a144c33705546355afccf0cf39b188f3cdb48b852309',
  };
}

export function verifyDigest(bytes: Uint8Array, expected: string) {
  const actual = createHash('sha256').update(bytes).digest('hex');
  if (actual !== expected) throw new Error(`artifact SHA-256 mismatch: expected ${expected}, received ${actual}`);
}

export async function install() {
  const artifact = selectArtifact(process.arch);
  const response = await fetch(artifact.url, { signal: AbortSignal.timeout(120_000) });
  if (!response.ok) throw new Error(`download ${artifact.url}: HTTP ${response.status}`);
  const bytes = new Uint8Array(await response.arrayBuffer());
  verifyDigest(bytes, artifact.sha256);
  const scratch = mkdtempSync(join(tmpdir(), 'jq-install-'));
  try {
    const candidate = join(scratch, 'jq');
    writeFileSync(candidate, bytes);
    chmodSync(candidate, 0o755);
    const version = execFileSync(candidate, ['--version'], { encoding: 'utf8' }).trim();
    if (version !== `jq-${VERSION}`) throw new Error(`artifact reports unexpected version ${version}`);
    mkdirSync('/usr/local/bin', { recursive: true });
    // Stage beside the destination so the final rename stays on one filesystem.
    const staged = mkdtempSync('/usr/local/bin/.jq-install-');
    try {
      const stagedBinary = join(staged, 'jq');
      writeFileSync(stagedBinary, bytes, { mode: 0o755 });
      renameSync(stagedBinary, DESTINATION);
    } finally {
      rmSync(staged, { recursive: true, force: true });
    }
    const effective = execFileSync('/bin/sh', ['-c', 'command -v jq'], { encoding: 'utf8' }).trim();
    if (effective !== DESTINATION) throw new Error(`PATH resolves jq to ${effective}, expected ${DESTINATION}`);
    console.log(`jq installed: artifact=${artifact.name} sha256=${artifact.sha256} version=${version} path=${effective}`);
  } finally {
    rmSync(scratch, { recursive: true, force: true });
  }
}
