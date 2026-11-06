#!/usr/bin/env python3
"""Refresh a concrete host SSH alias from a Dev Container lifecycle ID."""
import argparse
import json
import os
from pathlib import Path
import re
import secrets
import subprocess
import sys
import tempfile

MARKER = '# Managed by devcontainer refresh-ssh-alias.py\n'


def fail(problem, consequence, remedy):
    raise RuntimeError(f'{problem} {consequence} {remedy}')


def execute(args):
    try:
        return subprocess.run(args, text=True, capture_output=True)
    except OSError as exc:
        fail(f'{exc}\n{args[0]} could not be launched.',
             'The alias was not refreshed.',
             f'Make {args[0]} available and executable on PATH, then retry.')


def run(args):
    result = execute(args)
    if result.returncode:
        fail(f'{args[0]} output:\n{result.stdout}{result.stderr}\n'
             f'{args[0]} failed (exit {result.returncode}).',
             'The alias was not refreshed.', f'Resolve the {args[0]} failure and retry.')
    return result.stdout


def resolved(alias, managed=None, normalized=False):
    options = ['-o', 'HostName=127.0.0.1', '-o', 'Port=2222', '-o', 'User=codexprobe'] if normalized else []
    command = execute(['ssh', '-vG', *options, alias])
    if command.returncode:
        fail(f'ssh output:\n{command.stdout}{command.stderr}\n'
             f'ssh failed (exit {command.returncode}).',
             'The alias was not refreshed.', 'Resolve the SSH failure and retry.')
    for line in command.stderr.splitlines():
        match = re.match(r'^debug1: (.+) line [0-9]+: Applying options for (.+)$', line)
        if match and any(part.lower() == alias.lower() for part in match.group(2).split()):
            if managed is None or Path(match.group(1)) != managed:
                fail('An existing SSH Host entry names the requested alias.',
                     'Existing settings were preserved.', 'Choose an unused alias or resolve that entry.')
    result = {}
    for line in command.stdout.splitlines():
        key, _, value = line.partition(' ')
        if key not in result:
            result[key] = []
        result[key].append(value)
    if not all(k in result for k in ('hostname', 'port', 'user')):
        fail('SSH configuration output lacks connection fields.',
             'The alias cannot be checked.', 'Correct the SSH configuration and retry.')
    return result


def equivalent_option(left, right, alias, probe):
    """Compare unchanged text and corresponding original-host expansions."""
    if left == right:
        return True
    pending = [(0, 0)]
    visited = set()
    while pending:
        i, j = pending.pop()
        if (i, j) in visited:
            continue
        visited.add((i, j))
        if i == len(left) and j == len(right):
            return True
        if i < len(left) and j < len(right) and left[i] == right[j]:
            pending.append((i + 1, j + 1))
        if left.startswith(alias, i) and right.startswith(probe, j):
            pending.append((i + len(alias), j + len(probe)))
    return False


def equivalent_settings(actual, baseline, alias, probe):
    ignored = {'host', 'hostname', 'port', 'user'}
    actual_keys = actual.keys() - ignored
    baseline_keys = baseline.keys() - ignored
    if actual_keys != baseline_keys:
        return False
    for key in actual_keys:
        left, right = actual[key], baseline[key]
        if len(left) != len(right) or any(
                not equivalent_option(a, b, alias, probe) for a, b in zip(left, right)):
            return False
    return True


def main():
    global managed_path, replacement_started, rollback_done
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('workspace', 'container', 'alias', 'user'):
        parser.add_argument('--' + name, required=True)
    args = parser.parse_args()
    problems = []
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]*', args.alias):
        problems.append('alias: use letters, digits, dot, underscore or hyphen')
    if not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_-]*', args.user):
        problems.append('user: supply the configured container user name')
    if not re.fullmatch(r'[0-9a-f]{12,64}', args.container):
        problems.append('container ID: pass containerId returned by devcontainer up')
    workspace = Path(args.workspace)
    if not workspace.is_absolute() or not workspace.is_dir():
        problems.append('workspace: supply an existing absolute consuming workspace path')
    if problems:
        fail('Invalid inputs: ' + '; '.join(problems) + '.', 'No configuration was changed.',
             'Correct all listed inputs and retry.')
    try:
        inspected = json.loads(run(['docker', 'inspect', args.container]))
        if not isinstance(inspected, list) or len(inspected) != 1:
            raise ValueError('expected exactly one container')
        container = inspected[0]
        identity = container['Id']
        labels = container['Config']['Labels'] or {}
        bindings = container['NetworkSettings']['Ports']['2222/tcp']
        if not isinstance(identity, str) or not identity.startswith(args.container):
            raise ValueError('container ID does not match')
        if not container['State']['Running']:
            raise ValueError('container is not running')
        label = labels.get('devcontainer.local_folder')
        if not label or os.path.realpath(label) != os.path.realpath(workspace):
            raise ValueError('workspace label does not match')
        if not isinstance(bindings, list) or len(bindings) != 1:
            raise ValueError('expected exactly one SSH mapping')
        binding = bindings[0]
        port_text = binding['HostPort']
        if binding['HostIp'] != '127.0.0.1' or not re.fullmatch(r'[0-9]+', port_text):
            raise ValueError('SSH mapping is not a numeric IPv4 loopback port')
        port = int(port_text)
        if not 1 <= port <= 65535:
            raise ValueError('SSH port is out of range')
    except (ValueError, KeyError, TypeError, json.JSONDecodeError) as exc:
        fail(f'Container inspection is unresolved: {exc}.', 'No mapping was selected.',
             'Recreate the intended workspace and pass its returned container ID.')

    directory = Path.home() / '.ssh' / 'codex-devcontainers'
    target = directory / (args.alias + '.conf')
    managed_path = target
    if directory.is_symlink() or target.is_symlink():
        fail('The managed directory or fragment is a symlink.', 'No configuration was changed.',
             'Use a regular managed directory and fragment.')
    old = target.read_text() if target.exists() else None
    old_fields = None
    if old is not None:
        match = re.fullmatch(re.escape(MARKER) + r'Host ([A-Za-z0-9_.-]+)\n  HostName 127\.0\.0\.1\n  Port ([0-9]+)\n  User ([A-Za-z_][A-Za-z0-9_-]*)\n', old)
        if not match or match.group(1) != args.alias:
            fail('The alias fragment is not a recognized managed entry.',
                 'It was preserved.', 'Choose another alias or resolve the existing fragment.')
        old_fields = {'hostname': ['127.0.0.1'], 'port': [match.group(2)], 'user': [match.group(3)]}
    before = resolved(args.alias, target)
    probe_alias = 'codex-probe-' + secrets.token_hex(12)
    baseline_raw = resolved(probe_alias)
    baseline = resolved(probe_alias, normalized=True)
    comparable = resolved(args.alias, target, normalized=True)
    selected = {k: before[k] for k in ('hostname', 'port', 'user')}
    if (old_fields and selected != old_fields) or (not old_fields and
            (before['hostname'] != [args.alias.lower()] or any(before[k] != baseline_raw[k] for k in ('port', 'user')))) or not equivalent_settings(comparable, baseline, args.alias, probe_alias):
        fail('The alias conflicts with existing SSH configuration or its managed include is inactive.',
             'Existing settings were preserved.', 'Choose an unused alias and enable the documented Include before retrying.')
    content = f'{MARKER}Host {args.alias}\n  HostName 127.0.0.1\n  Port {port}\n  User {args.user}\n'
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    fd, temp = tempfile.mkstemp(prefix='.refresh-', dir=directory)
    try:
        with os.fdopen(fd, 'w') as stream:
            stream.write(content)
        os.replace(temp, target)
        replacement_started = True
        try:
            after = resolved(args.alias, target)
            if {k: after[k] for k in ('hostname', 'port', 'user')} != {'hostname': ['127.0.0.1'], 'port': [str(port)], 'user': [args.user]}:
                fail('SSH does not select the managed alias.', 'The refreshed fragment cannot be used.',
                     'Place the documented Include before conflicting Host or Match settings and retry.')
        except Exception as original:
            try:
                if old is None:
                    target.unlink()
                else:
                    target.write_text(old)
                rollback_done = True
            except OSError as rollback_error:
                raise RuntimeError(
                    f'{original}\nRollback error: {rollback_error}\n'
                    f'The managed SSH path {target} could not be restored. '
                    'The fragment may still contain the new mapping. '
                    'Inspect the fragment and restore the prior entry before retrying.'
                ) from rollback_error
            action = 'removed' if old is None else 'restored'
            raise RuntimeError(f'{original}\nThe managed fragment was {action}.') from original
    finally:
        if os.path.exists(temp):
            os.unlink(temp)
    print(f'{args.alias} -> 127.0.0.1:{port} ({identity})')


managed_path = None
replacement_started = False
rollback_done = False


if __name__ == '__main__':
    try:
        main()
    except OSError as exc:
        state = ('the prior fragment was restored' if rollback_done else
                 'the fragment may have changed and rollback is unconfirmed' if replacement_started else
                 'the alias was not refreshed')
        print(f'{exc}\nThe managed SSH path {managed_path or "unavailable before the managed path was selected"} failed. '
              f'{state.capitalize()}. Check that the managed directory is writable and the fragment '
              'is a regular file, resolve the reported failure, and retry.', file=sys.stderr)
        sys.exit(1)
    except RuntimeError as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)
