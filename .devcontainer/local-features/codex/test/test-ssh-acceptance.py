#!/usr/bin/env python3
"""Exercise acceptance-only config wiring with real isolated OpenSSH; no Docker."""
import os
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[4]
BRIDGE = Path(os.environ.get('SSH_ACCEPTANCE_BRIDGE', ROOT / 'scripts/ssh-acceptance-config.py'))
TOKEN = '1' * 32


class BridgeTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / 'test space'
        self.root.mkdir(mode=0o700)
        (self.root / 'key').write_text('synthetic test key')
        (self.root / 'key').chmod(0o600)
        self.config = Path(self.temp.name) / 'config'
        self.original = b'Host unrelated\n  User other\nHost *\n  ControlMaster auto\n  ControlPath /some/user/socket-%n\n'
        self.config.write_bytes(self.original)
        self.config.chmod(0o600)
        self.ssh = shutil.which('ssh')
        self.assertIsNotNone(self.ssh)

    def run_bridge(self, action):
        return subprocess.run(['python3', str(BRIDGE), action, '--config', str(self.config), '--root', str(self.root), '--token', TOKEN], text=True, capture_output=True)

    def resolved(self, host):
        return subprocess.run([self.ssh, '-G', '-F', str(self.config), host], text=True, capture_output=True, check=True).stdout

    def test_bridge_selects_only_test_aliases_and_preserves_edits(self):
        before = self.resolved('unrelated')
        result = self.run_bridge('install')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(before, self.resolved('unrelated'))
        bin_dir = self.root / 'bin'
        bin_dir.mkdir()
        docker = bin_dir / 'docker'
        docker.write_text('#!/bin/sh\n/bin/cat "$DOCKER_FIXTURE"\n')
        docker.chmod(0o755)
        workspace = self.root / 'workspace'
        workspace.mkdir()
        fixture = self.root / 'docker.json'
        container_id = 'a' * 64
        fixture.write_text(json.dumps([{'Id': container_id, 'State': {'Running': True}, 'Config': {'Labels': {'devcontainer.local_folder': str(workspace)}}, 'NetworkSettings': {'Ports': {'2222/tcp': [{'HostIp': '127.0.0.1', 'HostPort': '45001'}]}}}]))
        env = dict(os.environ, HOME=str(self.root / 'fake-home'), DOCKER_FIXTURE=str(fixture), PATH=str(bin_dir) + ':' + os.environ['PATH'])
        for suffix in ('a', 'b'):
            alias = 'codex-accept-' + TOKEN + '-' + suffix
            result = subprocess.run(['python3', str(ROOT / 'scripts/refresh-ssh-alias.py'), '--workspace', str(workspace), '--container', container_id, '--alias', alias, '--user', 'devcontainer', '--ssh-config', str(self.root / 'ssh_config'), '--output-dir', str(self.root / 'fragments')], env=env, text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
        for suffix in ('a', 'b'):
            data = self.resolved('codex-accept-' + TOKEN + '-' + suffix)
            self.assertIn(f'identityfile {self.root}/key', data)
            self.assertIn(f'userknownhostsfile {self.root}/known_hosts', data)
            self.assertIn('identityagent none', data)
            self.assertIn('port 45001', data)
            self.assertIn('stricthostkeychecking ask', data)
            self.assertIn('controlmaster false', data)
            self.assertNotIn('controlpath ', data)
        with self.config.open('ab') as stream:
            stream.write(b'# unrelated later edit\n')
        result = self.run_bridge('remove')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.config.read_bytes(), self.original + b'# unrelated later edit\n')

    def test_cleanup_refuses_changed_block(self):
        self.assertEqual(self.run_bridge('install').returncode, 0)
        changed = self.config.read_bytes().replace(b'Host *\n', b'Host altered\n', 1)
        self.config.write_bytes(changed)
        result = self.run_bridge('remove')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.config.read_bytes(), changed)
        self.assertIn('acceptance block', result.stderr)

    def test_preexisting_alias_is_preserved(self):
        self.config.write_text(f'Host codex-accept-{TOKEN}-a\n  Port 4444\n')
        before = self.config.read_bytes()
        result = self.run_bridge('install')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.config.read_bytes(), before)
        self.assertIn('alias', result.stderr)

    def test_existing_private_targets_are_preserved(self):
        for name in ('ssh_config', 'known_hosts', 'fragments'):
            with self.subTest(name=name):
                target = self.root / name
                target.symlink_to(self.root / 'missing')
                before = self.config.read_bytes()
                result = self.run_bridge('install')
                self.assertNotEqual(result.returncode, 0)
                self.assertTrue(target.is_symlink())
                self.assertEqual(self.config.read_bytes(), before)
                target.unlink()

    def test_test_key_must_be_private_and_unshared(self):
        key = self.root / 'key'
        key.chmod(0o644)
        result = self.run_bridge('install')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.config.read_bytes(), self.original)
        self.assertIn('test identity', result.stderr)
        key.chmod(0o600)
        (self.root / 'other-link').hardlink_to(key)
        result = self.run_bridge('install')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.config.read_bytes(), self.original)
        self.assertIn('test identity', result.stderr)

    def test_invalid_token_and_symlinked_config_fail_closed(self):
        original = self.config.read_bytes()
        bad = subprocess.run(['python3', str(BRIDGE), 'install', '--config', str(self.config), '--root', str(self.root), '--token', '../bad'], text=True, capture_output=True)
        self.assertNotEqual(bad.returncode, 0)
        self.assertEqual(self.config.read_bytes(), original)
        link = self.root.parent / 'config-link'
        link.symlink_to(self.config)
        bad = subprocess.run(['python3', str(BRIDGE), 'install', '--config', str(link), '--root', str(self.root), '--token', TOKEN], text=True, capture_output=True)
        self.assertNotEqual(bad.returncode, 0)
        self.assertEqual(self.config.read_bytes(), original)
        self.assertTrue(link.is_symlink())

    def test_other_identity_is_not_used_or_overwritten(self):
        self.config.write_text('Host *\n  IdentityFile /different/user/key\n')
        before = self.config.read_bytes()
        result = self.run_bridge('install')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.config.read_bytes(), before)
        self.assertIn('test identity', result.stderr)


if __name__ == '__main__':
    unittest.main()
