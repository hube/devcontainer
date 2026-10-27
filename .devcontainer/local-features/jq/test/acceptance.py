#!/usr/bin/env python3
"""Live acceptance probe, not a unit test of upstream jq internals."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys

binary = str(Path(sys.argv[1]).resolve())
out = Path(sys.argv[2])
out.mkdir(parents=True, exist_ok=False)
print(f"binary={binary}")
print(subprocess.check_output([binary, '--version'], text=True).strip())
print(f"sha256={hashlib.sha256(Path(binary).read_bytes()).hexdigest()}")
# Vary alignment around a raw-input buffer boundary using a self-contained body.
fixtures = {'control': 'Small text — 日本語 😃\n'}
for offset in range(1, 5):
    fixtures[f'boundary-{offset}'] = '0' * offset + '😃' * 3000
fixtures['large'] = '# Publication body\n' + ('- 日本語の公開本文を完全に保持 — 😃 `code`\n' * 2200)
failed = []
for name, text in fixtures.items():
    source = out / f'{name}.md'
    source.write_bytes(text.encode('utf-8'))
    for route in ('stdin', 'file'):
        command = [binary, '-Rs', '{body: .}']
        result = subprocess.run(command + ([str(source)] if route == 'file' else []),
                                input=source.read_bytes() if route == 'stdin' else None,
                                capture_output=True, check=True)
        (out / f'{name}-{route}.json').write_bytes(result.stdout)
        decoded = json.loads(result.stdout)['body']
        equal = decoded == text
        print(f'{name}/{route}: exact={equal} bytes={len(source.read_bytes())}')
        if not equal:
            failed.append(f'{name}/{route}')
if failed:
    print('Decoded publication text differs: ' + ', '.join(failed), file=sys.stderr)
    print('Problem: this binary changes publication text.\n'
          'Consequence: intact Unicode publication is not established.\n'
          'Remedy: adopt the corrected image input and repeat acceptance.', file=sys.stderr)
    sys.exit(1)
