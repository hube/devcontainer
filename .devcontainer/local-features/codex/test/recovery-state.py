#!/usr/bin/env python3
"""Capture and compare the explicitly protected disposable acceptance state."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys


def git(repo, *args):
    result = subprocess.run(
        ["git", f"--git-dir={repo}", *args], capture_output=True, text=True
    )
    if result.returncode:
        raise RuntimeError(result.stdout + result.stderr)
    return result.stdout


def stored_ref(path):
    if path.is_symlink():
        raise RuntimeError(f"symbolic-link ref storage is unsupported: {path}")
    value = path.read_text().strip()
    if value.startswith("ref: "):
        return {"oid": None, "symbolic_target": value.removeprefix("ref: ")}
    return {"oid": value, "symbolic_target": None}


def references(repo):
    if git(repo, "rev-parse", "--show-ref-format").strip() != "files":
        raise RuntimeError("acceptance repository must use files ref storage")
    refs = {}
    packed = repo / "packed-refs"
    if packed.exists():
        for line in packed.read_text().splitlines():
            if line and not line.startswith(("#", "^")):
                oid, name = line.split(" ", 1)
                refs[name] = {"oid": oid, "symbolic_target": None}
    # Loose refs include unborn targets and override packed entries of the same name.
    def scan_error(error):
        raise error

    for directory, directories, filenames in os.walk(repo / "refs", onerror=scan_error):
        for name in directories:
            if (Path(directory) / name).is_symlink():
                raise RuntimeError(f"symbolic-link ref directory is unsupported: {name}")
        for filename in filenames:
            path = Path(directory) / filename
            if path.name.endswith(".lock"):
                continue
            name = path.relative_to(repo).as_posix()
            git(repo, "check-ref-format", name)
            refs[name] = stored_ref(path)
    return refs, stored_ref(repo / "HEAD")


def capture(args):
    repo = Path(args.repo).resolve()
    files = [Path(item).resolve() for item in args.file]
    failures = []
    if not repo.is_dir():
        failures.append(f"repository directory missing: {repo}")
    for path in files:
        if not path.is_file():
            failures.append(f"protected file missing: {path}")
    if failures:
        raise RuntimeError("\n".join(failures))
    refs, head_state = references(repo)
    registrations = {}
    for block in git(repo, "worktree", "list", "--porcelain").strip().split("\n\n"):
        path = block.splitlines()[0].removeprefix("worktree ")
        registrations[path] = block
    receipt = repo / "FETCH_HEAD"
    return {
        "repo": str(repo),
        "refs": refs,
        "head": head_state,
        "worktrees": registrations,
        "files": {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in files},
        "fetch_head": hashlib.sha256(receipt.read_bytes()).hexdigest() if receipt.exists() else None,
    }


def compare(args):
    baseline = json.loads(Path(args.baseline).read_text())
    actual = json.loads(Path(args.actual).read_text())
    failures = []
    for name in ("repo", "head", "files", "fetch_head"):
        if baseline[name] != actual[name]:
            failures.append(f"protected {name} changed")
    for name, allowed in (("refs", args.allow_ref), ("worktrees", args.allow_worktree)):
        for key, value in baseline[name].items():
            if actual[name].get(key) != value:
                failures.append(f"protected {name} entry changed or missing: {key}")
        extras = actual[name].keys() - baseline[name].keys()
        for key in sorted(extras - set(allowed)):
            failures.append(f"undeclared {name} addition: {key}")
    if failures:
        raise RuntimeError("\n".join(failures))
    print("Protected acceptance state preserved; additions match the supplied allowlists.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    snapshot = commands.add_parser("capture")
    snapshot.add_argument("--repo", required=True)
    snapshot.add_argument("--file", action="append", required=True)
    check = commands.add_parser("compare")
    check.add_argument("baseline")
    check.add_argument("actual")
    check.add_argument("--allow-ref", action="append", default=[])
    check.add_argument("--allow-worktree", action="append", default=[])
    args = parser.parse_args()
    try:
        if args.command == "capture":
            print(json.dumps(capture(args), indent=2, sort_keys=True))
        else:
            compare(args)
    except (OSError, RuntimeError, ValueError, KeyError) as error:
        print(str(error), file=sys.stderr)
        print(
            "Recovery acceptance state could not be captured or compared. "
            "Preservation has not been established. Restore the reported fixture "
            "input or protected entry, declare only intended additions, and rerun.",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
