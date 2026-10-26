import { install } from './install';

install().catch((error: unknown) => {
  console.error(error instanceof Error ? error.stack : String(error));
  console.error('jq: the corrected publication input could not be installed.');
  console.error('The image build cannot establish Unicode-preserving jq selection.');
  console.error('Remedy: resolve the reported download, digest, architecture or PATH failure and rebuild this image.');
  process.exitCode = 1;
});
