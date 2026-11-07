#!/usr/bin/env python3
"""Expose two disposable SSH aliases and remove only their marked block."""
import argparse
import importlib.util
import os
from pathlib import Path
import re
import secrets
import stat
import subprocess
import sys
import tempfile


def fail(problem, consequence, remedy):
    raise RuntimeError(f'{problem} {consequence} {remedy}')


def quote(path):
    return '"' + str(path).replace('\\', '\\\\').replace('"', '\\"') + '"'


def atomic_change(path, before, after):
    info = path.lstat()
    if not stat.S_ISREG(info.st_mode) or info.st_nlink != 1:
        fail(f'SSH config {path} is not an unshared regular file.',
             'It was preserved.', 'Use a regular config file and retry.')
    fd, name = tempfile.mkstemp(prefix='.codex-accept-', dir=path.parent)
    try:
        os.fchmod(fd, stat.S_IMODE(info.st_mode))
        with os.fdopen(fd, 'wb') as stream:
            stream.write(after)
        now = path.lstat()
        if (now.st_dev, now.st_ino, now.st_mode) != (info.st_dev, info.st_ino, info.st_mode) or path.read_bytes() != before:
            fail(f'SSH config {path} changed during the operation.',
                 'The newer contents were preserved.', 'Retry after concurrent edits finish.')
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def resolved(config, alias):
    options = ['-F', str(config)] if config is not None else []
    try:
        command = subprocess.run(['ssh', '-G', *options, alias], text=True, capture_output=True)
    except OSError as exc:
        fail(f'{exc}\nssh could not be launched.', 'The acceptance block was not kept.',
             'Make ssh available and executable on PATH, then retry.')
    if command.returncode:
        fail(f'ssh output:\n{command.stdout}{command.stderr}\nSSH config evaluation failed.',
             'The acceptance block was not kept.', 'Correct the SSH config and retry.')
    values = {}
    for line in command.stdout.splitlines():
        key, _, value = line.partition(' ')
        values.setdefault(key, []).append(value.strip('"'))
    return values


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('install', 'remove'))
    parser.add_argument('--config', required=True)
    parser.add_argument('--root', required=True)
    parser.add_argument('--token', required=True)
    args = parser.parse_args()
    config, root = Path(args.config), Path(args.root)
    problems = []
    if not config.is_absolute() or config.is_symlink() or not config.is_file():
        problems.append('SSH config must be an existing absolute regular file')
    if (not root.is_absolute() or any(ord(c) < 32 for c in str(root)) or root.is_symlink() or not root.is_dir() or
            root.stat().st_uid != os.getuid() or root.stat().st_mode & 0o077):
        problems.append('test root must be an absolute private owned directory')
    if not re.fullmatch('[0-9a-f]{32}', args.token):
        problems.append('token must be 32 lowercase hexadecimal characters')
    if problems:
        fail('Invalid acceptance inputs: ' + '; '.join(problems) + '.',
             'No SSH config was changed.', 'Correct the listed inputs and retry.')
    ssh_config = None if config == Path.home() / '.ssh' / 'config' else config
    aliases = [f'codex-accept-{args.token}-{suffix}' for suffix in ('a', 'b')]
    private = root / 'ssh_config'
    fragments = root / 'fragments'
    key = root / 'key'
    known = root / 'known_hosts'
    begin = f'# BEGIN codex-ssh-acceptance {args.token}\n'
    end = f'# END codex-ssh-acceptance {args.token}\n'
    block = (begin + f'Host {aliases[0]} {aliases[1]}\n  Include {quote(private)}\nHost *\n' + end).encode()
    before = config.read_bytes()
    if args.action == 'remove':
        if before.count(block) != 1 or before.count(begin.encode()) != 1 or before.count(end.encode()) != 1:
            fail('The expected acceptance block is missing, duplicated or changed.',
                 'The SSH config was preserved.', 'Inspect the marked block and remove only the intended test settings.')
        atomic_change(config, before, before.replace(block, b'', 1))
        print('Removed the acceptance block; other SSH config bytes were retained.')
        return
    if begin.encode() in before or end.encode() in before or any(p.exists() or p.is_symlink() for p in (private, fragments, known)):
        fail('The acceptance block or its private paths already exist.',
             'Existing settings were preserved.', 'Choose a new private root and token.')
    if (key.is_symlink() or not key.is_file() or key.stat().st_uid != os.getuid() or
            key.stat().st_nlink != 1 or key.stat().st_mode & 0o077):
        fail('The test identity is missing, shared, or not private.',
             'The SSH config was not changed.', 'Generate a private, unshared test key in the private root and retry.')
    helper_path = Path(__file__).with_name('refresh-ssh-alias.py')
    sys.dont_write_bytecode = True
    spec = importlib.util.spec_from_file_location('ssh_alias_helper', helper_path)
    helper = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(helper)
    probe = 'codex-probe-' + secrets.token_hex(12)
    baseline_raw = helper.resolved(probe, ssh_config=ssh_config)
    baseline = helper.resolved(probe, normalized=True, ssh_config=ssh_config)
    for alias in aliases:
        actual = helper.resolved(alias, ssh_config=ssh_config)
        comparable = helper.resolved(alias, normalized=True, ssh_config=ssh_config)
        if (actual['hostname'] != [alias.lower()] or
                any(actual[k] != baseline_raw[k] for k in ('port', 'user')) or
                not helper.equivalent_settings(comparable, baseline, alias, probe)):
            fail(f'The test alias {alias} conflicts with existing SSH settings.',
                 'The SSH config was preserved.', 'Choose a fresh test token and retry.')
    fragments.mkdir(mode=0o700)
    private.write_text(f'Include {quote(fragments / "*.conf")}\nHost *\n  IdentityFile {quote(key)}\n  UserKnownHostsFile {quote(known)}\n  IdentityAgent none\n  IdentitiesOnly yes\n  StrictHostKeyChecking ask\n  ControlMaster no\n  ControlPath none\n')
    private.chmod(0o600)
    atomic_change(config, before, block + before)
    try:
        for alias in aliases:
            settings = resolved(ssh_config, alias)
            if (settings.get('identityfile') != [str(key)] or
                    settings.get('userknownhostsfile') != [str(known)] or
                    settings.get('identityagent') != ['none'] or
                    settings.get('identitiesonly') != ['yes'] or
                    settings.get('stricthostkeychecking') != ['ask'] or
                    settings.get('controlmaster') != ['false'] or settings.get('controlpath')):
                fail('The test identity or known-host settings are not isolated.',
                     'The acceptance block cannot be used safely.',
                     'Inspect inherited SSH settings and choose a separate test environment.')
    except Exception as original:
        current = config.read_bytes()
        if current.count(block) != 1:
            fail(f'{original}\nThe acceptance block changed during setup.',
                 'Automatic removal was not attempted.', 'Inspect and remove only the marked test block.')
        try:
            atomic_change(config, current, current.replace(block, b'', 1))
        except (OSError, RuntimeError) as rollback_error:
            fail(f'{original}\nRollback error: {rollback_error}\nThe acceptance block could not be removed.',
                 'The test block may remain in the SSH config.',
                 'Inspect the marked block and remove only the intended test settings.')
        raise
    print('\n'.join(aliases))


if __name__ == '__main__':
    try:
        main()
    except OSError as exc:
        print(f'{exc}\nThe test SSH setup or cleanup failed. The SSH config may contain a test block. '
              'Inspect the reported path and marked block, correct access, and retry.', file=sys.stderr)
        sys.exit(1)
    except RuntimeError as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)
