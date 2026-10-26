import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { selectArtifact, verifyDigest } from '../src/jq/install';

describe('published jq input', () => {
  it('selects the official digest and release for the published ARM64 target', () => {
    expect(selectArtifact('arm64')).toEqual({
      name: 'jq-linux-arm64',
      url: 'https://github.com/jqlang/jq/releases/download/jq-1.8.2/jq-linux-arm64',
      sha256: '8b85c817833814ddca00a144c33705546355afccf0cf39b188f3cdb48b852309',
    });
  });

  it.each(['x64', 'arm', 's390x', ''])('rejects an unpublished target: %s', (architecture) => {
    expect(() => selectArtifact(architecture)).toThrow('unsupported architecture');
  });

  it('accepts exact bytes and refuses a changed download', () => {
    const bytes = Buffer.from('controlled artifact bytes');
    const digest = createHash('sha256').update(bytes).digest('hex');
    expect(() => verifyDigest(bytes, digest)).not.toThrow();
    expect(() => verifyDigest(Buffer.from('altered artifact bytes'), digest)).toThrow('artifact SHA-256 mismatch');
  });

  it('declares its interpreter dependency and is consumed by the published configuration', () => {
    const feature = JSON.parse(readFileSync('.devcontainer/local-features/jq/devcontainer-feature.json', 'utf8'));
    expect(feature.dependsOn['ghcr.io/devcontainers/features/node:2']).toEqual({});
    expect(readFileSync('.devcontainer/devcontainer.json', 'utf8')).toContain('"./local-features/jq": {}');
    expect(readFileSync('.github/workflows/publish.yaml', 'utf8')).toContain('runs-on: ubuntu-24.04-arm');
    expect(readFileSync('.github/workflows/tests.yml', 'utf8')).toContain('.devcontainer/local-features/jq/dist/');
  });
});
