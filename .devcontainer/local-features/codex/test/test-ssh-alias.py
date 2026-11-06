#!/usr/bin/env python3
"""Exercise the helper with named Docker and SSH stubs; no daemon or keys used."""
import json
import os
from pathlib import Path
import subprocess
import sys
import shutil
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[4]
HELPER = Path(os.environ.get('SSH_ALIAS_HELPER', ROOT / 'scripts/refresh-ssh-alias.py'))
ID = 'a' * 64


class AliasTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.home = self.root / 'home'
        self.home.mkdir()
        self.workspace = self.root / 'workspace'
        self.workspace.mkdir()
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.data = self.root / 'inspect.json'
        self.container = {'Id': ID, 'State': {'Running': True},
                          'Config': {'Labels': {'devcontainer.local_folder': str(self.workspace)}},
                          'NetworkSettings': {'Ports': {'2222/tcp': [{'HostIp': '127.0.0.1', 'HostPort': '45001'}]}}}
        (self.bin / 'docker').write_text('#!/bin/sh\ncat "$DOCKER_FIXTURE"\n')
        (self.bin / 'ssh').write_text('''#!/usr/bin/env python3
import os, pathlib, sys
alias = sys.argv[-1]
path = pathlib.Path(os.environ['HOME']) / '.ssh/codex-devcontainers' / (alias + '.conf')
print('hostname ' + alias + '\\nport 22\\nuser default') if not path.exists() else print('\\n'.join(line.strip().lower() for line in path.read_text().splitlines() if line.strip().startswith(('HostName ', 'Port ', 'User '))))
''')
        for path in self.bin.iterdir():
            path.chmod(0o755)
        self.env = dict(os.environ, HOME=str(self.home), DOCKER_FIXTURE=str(self.data), PATH=str(self.bin) + ':' + os.environ['PATH'])
        self.target = self.home / '.ssh/codex-devcontainers/demo.conf'

    def invoke(self, alias='demo'):
        self.data.write_text(json.dumps([self.container]))
        return subprocess.run(['python3', str(HELPER), '--workspace', str(self.workspace), '--container', ID, '--alias', alias, '--user', 'devcontainer'], env=self.env, text=True, capture_output=True)

    def test_refresh_and_preserve_another_alias(self):
        self.assertEqual(self.invoke().returncode, 0)
        other = self.target.with_name('other.conf')
        other.write_text('user-owned bytes\n')
        self.container['NetworkSettings']['Ports']['2222/tcp'][0]['HostPort'] = '45002'
        result = self.invoke()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('Port 45002\n', self.target.read_text())
        self.assertEqual(other.read_text(), 'user-owned bytes\n')

    def test_wrong_workspace_and_stopped_container(self):
        for mutation in ('workspace', 'stopped'):
            with self.subTest(mutation=mutation):
                original = json.loads(json.dumps(self.container))
                if mutation == 'workspace':
                    self.container['Config']['Labels']['devcontainer.local_folder'] = '/other'
                else:
                    self.container['State']['Running'] = False
                result = self.invoke()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('Container inspection is unresolved', result.stderr)
                self.assertFalse(self.target.exists())
                self.container = original

    def test_missing_ambiguous_and_non_loopback_mappings(self):
        for bindings in (None, [], [{'HostIp': '127.0.0.1', 'HostPort': '1'}, {'HostIp': '127.0.0.1', 'HostPort': '2'}], [{'HostIp': '0.0.0.0', 'HostPort': '2222'}]):
            with self.subTest(bindings=bindings):
                self.container['NetworkSettings']['Ports']['2222/tcp'] = bindings
                result = self.invoke()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('Container inspection is unresolved', result.stderr)
                self.assertFalse(self.target.exists())

    def test_unmanaged_fragment_preserved(self):
        self.target.parent.mkdir(parents=True)
        self.target.write_text('Host demo\n  Port 42\n')
        result = self.invoke()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('not a recognized managed entry', result.stderr)
        self.assertEqual(self.target.read_text(), 'Host demo\n  Port 42\n')

    def test_ssh_conflict_preserves_managed_fragment(self):
        self.assertEqual(self.invoke().returncode, 0)
        before = self.target.read_bytes()
        (self.bin / 'ssh').write_text('#!/bin/sh\nprintf "hostname other\\nport 22\\nuser somebody\\n"\n')
        result = self.invoke()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('alias conflicts', result.stderr)
        self.assertEqual(self.target.read_bytes(), before)

    def test_stale_id_and_missing_workspace_label(self):
        for field in ('id', 'label'):
            with self.subTest(field=field):
                original = json.loads(json.dumps(self.container))
                if field == 'id':
                    self.container['Id'] = 'b' * 64
                else:
                    self.container['Config']['Labels'] = {}
                result = self.invoke()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('Container inspection is unresolved', result.stderr)
                self.assertFalse(self.target.exists())
                self.container = original

    def test_missing_include_rolls_back_new_fragment(self):
        (self.bin / 'ssh').write_text('#!/bin/sh\nprintf "hostname demo\\nport 22\\nuser default\\n"\n')
        result = self.invoke()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('SSH does not select the managed alias', result.stderr)
        self.assertFalse(self.target.exists())

    def test_alias_specific_options_are_conflicts(self):
        (self.bin / 'ssh').write_text("""#!/bin/sh
for alias do :; done
if [ \"$alias\" = demo ]; then
  printf 'hostname demo\\nport 22\\nuser default\\nidentityfile /private/key\\n'
else
  printf 'hostname %s\\nport 22\\nuser default\\nidentityfile /default/key\\n' \"$alias\"
fi
""")
        result = self.invoke()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('alias conflicts', result.stderr)
        self.assertFalse(self.target.exists())

    def test_consumer_requests_native_loopback_allocation(self):
        config = (ROOT / '.devcontainer/devcontainer.json').read_text()
        import re
        data = json.loads(re.sub(r'^\s*//.*$', '', config, flags=re.MULTILINE))
        self.assertEqual(data['appPort'], ['127.0.0.1::2222'])

    def test_explicit_host_entry_is_a_conflict_even_with_default_values(self):
        (self.bin / 'ssh').write_text("""#!/bin/sh
for alias do :; done
if [ \"$alias\" = demo ]; then
  printf 'debug1: /home/example/.ssh/config line 2: Applying options for demo\\n' >&2
fi
printf 'hostname %s\\nport 22\\nuser default\\n' \"$alias\"
""")
        result = self.invoke()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('existing SSH Host entry names', result.stderr)
        self.assertFalse(self.target.exists())

    def test_real_ssh_inherited_controlpath(self):
        real_ssh = shutil.which('ssh')
        self.assertIsNotNone(real_ssh)
        config = self.root / 'ssh_config'
        config.write_text(f"Include {self.home}/.ssh/codex-devcontainers/*.conf\nHost *\n  ControlMaster auto\n  ControlPath /tmp/ssh-%n-%r@%h:%p\n")
        (self.bin / 'ssh').write_text(f'#!/bin/sh\nexec "{real_ssh}" -F "{config}" "$@"\n')
        result = self.invoke()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('Port 45001\n', self.target.read_text())

    def test_real_ssh_short_aliases_and_mixed_expansion(self):
        real_ssh = shutil.which('ssh')
        self.assertIsNotNone(real_ssh)
        config = self.root / 'ssh_config'
        config.write_text(f"Include {self.home}/.ssh/codex-devcontainers/*.conf\nHost *\n  ControlMaster auto\n  ControlPath /tmp/ssh-%n-%r@%h:%p\n")
        (self.bin / 'ssh').write_text(f'#!/bin/sh\nexec "{real_ssh}" -F "{config}" "$@"\n')
        for alias in ('dev', 'ssh', 'a', 'codex', 'MixedCase', 'fresh-consumer'):
            with self.subTest(alias=alias):
                result = self.invoke(alias)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn('Port 45001\n', self.target.with_name(alias + '.conf').read_text())

    def test_real_ssh_match_originalhost_connection_fields_are_conflicts(self):
        real_ssh = shutil.which('ssh')
        self.assertIsNotNone(real_ssh)
        config = self.root / 'ssh_config'
        (self.bin / 'ssh').write_text(f'#!/bin/sh\nexec "{real_ssh}" -F "{config}" "$@"\n')
        for directive in ('Port 4422', 'User someoneelse'):
            with self.subTest(directive=directive):
                config.write_text(f'Include {self.home}/.ssh/codex-devcontainers/*.conf\nMatch originalhost demo\n  {directive}\n')
                result = self.invoke()
                self.assertNotEqual(result.returncode, 0, result.stderr)
                self.assertIn('alias conflicts', result.stderr)
                self.assertFalse(self.target.exists())

    def test_real_ssh_alias_specific_identity_is_a_conflict(self):
        real_ssh = shutil.which('ssh')
        self.assertIsNotNone(real_ssh)
        config = self.root / 'ssh_config'
        config.write_text(f'Include {self.home}/.ssh/codex-devcontainers/*.conf\nMatch originalhost demo\n  IdentityFile /different/key\n')
        (self.bin / 'ssh').write_text(f'#!/bin/sh\nexec "{real_ssh}" -F "{config}" "$@"\n')
        original_config = config.read_bytes()
        result = self.invoke()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('alias conflicts', result.stderr)
        self.assertFalse(self.target.exists())
        self.assertEqual(config.read_bytes(), original_config)

    def test_missing_executables_are_diagnosed_at_launch(self):
        self.data.write_text(json.dumps([self.container]))
        empty = self.root / 'empty'
        empty.mkdir()
        args = [sys.executable, str(HELPER), '--workspace', str(self.workspace), '--container', ID, '--alias', 'demo', '--user', 'devcontainer']
        env = dict(self.env, PATH=str(empty))
        for executable in ('docker', 'ssh'):
            with self.subTest(executable=executable):
                if executable == 'ssh':
                    stub = empty / 'docker'
                    stub.write_text('#!/bin/sh\nexec /bin/cat "$DOCKER_FIXTURE"\n')
                    stub.chmod(0o755)
                result = subprocess.run(args, env=env, text=True, capture_output=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(f'{executable} could not be launched', result.stderr)
                self.assertIn('alias was not refreshed', result.stderr)
                self.assertIn(f'Make {executable} available and executable on PATH', result.stderr)
                self.assertNotIn('managed SSH path', result.stderr)

    def test_directory_at_fragment_has_actionable_error(self):
        self.target.mkdir(parents=True)
        result = self.invoke()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('managed SSH path', result.stderr)
        self.assertIn('was not refreshed', result.stderr)
        self.assertIn('regular file', result.stderr)
        self.assertTrue(self.target.is_dir())

    def test_replace_failure_reports_preserved_state(self):
        hooks = self.root / 'hooks'
        hooks.mkdir()
        (hooks / 'sitecustomize.py').write_text("""import os, sys
if sys.argv[0].endswith('refresh-ssh-alias.py'):
    def fail_replace(*args):
        raise PermissionError('fixture replace denied')
    os.replace = fail_replace
""")
        self.env['PYTHONPATH'] = str(hooks)
        result = self.invoke()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('fixture replace denied', result.stderr)
        self.assertIn('managed SSH path', result.stderr)
        self.assertIn('alias was not refreshed', result.stderr.lower())
        self.assertIn('regular file', result.stderr)
        self.assertFalse(self.target.exists())

    def test_rollback_failure_reports_both_failures(self):
        hooks = self.root / 'hooks'
        hooks.mkdir()
        (hooks / 'sitecustomize.py').write_text("""import os, sys
if sys.argv[0].endswith('refresh-ssh-alias.py'):
    original = os.unlink
    def guarded(path, *args, **kwargs):
        if str(path).endswith('/demo.conf'):
            raise PermissionError('fixture rollback denied')
        return original(path, *args, **kwargs)
    os.unlink = guarded
""")
        self.env['PYTHONPATH'] = str(hooks)
        (self.bin / 'ssh').write_text('#!/bin/sh\nprintf "hostname demo\\nport 22\\nuser default\\n"\n')
        result = self.invoke()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('SSH does not select the managed alias', result.stderr)
        self.assertIn('fixture rollback denied', result.stderr)
        self.assertIn('may still contain the new mapping', result.stderr)
        self.assertTrue(self.target.exists())

    def test_independent_bad_inputs_are_reported_together(self):
        result = subprocess.run(['python3', str(HELPER), '--workspace', str(self.root / 'absent'), '--container', 'bad', '--alias', 'bad alias', '--user', 'bad user'], env=self.env, text=True, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        for phrase in ('alias', 'user', 'container ID', 'workspace'):
            self.assertIn(phrase, result.stderr)

    def test_docker_failure_is_relayed(self):
        (self.bin / 'docker').write_text('#!/bin/sh\nprintf "fixture daemon failure\\n" >&2\nexit 7\n')
        result = self.invoke()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('docker output:\nfixture daemon failure\n\ndocker failed (exit 7)', result.stderr)
        self.assertFalse(self.target.exists())


if __name__ == '__main__':
    unittest.main()
