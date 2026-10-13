#!/usr/bin/env python3
"""Test our stored-ref capture; Git backend/name/registration diagnostics are stubbed."""

import argparse
import importlib.util
import json
from pathlib import Path
import tempfile
import sys
import unittest
from unittest.mock import patch


sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location(
    "recovery_state", Path(__file__).with_name("recovery-state.py")
)
state = importlib.util.module_from_spec(spec)
spec.loader.exec_module(state)


class StoredReferences(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.repo = Path(self.directory.name)
        self.write("HEAD", "ref: refs/fixture/chain\n")
        self.write("refs/fixture/leaf", "a" * 40 + "\n")
        self.write("refs/fixture/hop-a", "ref: refs/fixture/leaf\n")
        self.write("refs/fixture/hop-b", "ref: refs/fixture/leaf\n")
        self.write("refs/fixture/chain", "ref: refs/fixture/hop-a\n")
        self.write("refs/fixture/dangling", "ref: refs/heads/unborn-a\n")
        self.write("protected.txt", "protected\n")
        self.args = argparse.Namespace(repo=str(self.repo), file=[str(self.repo / "protected.txt")])

    def write(self, name, value):
        path = self.repo / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(value)

    def diagnostic(self, repo, *args):
        if args == ("rev-parse", "--show-ref-format"):
            return "files\n"
        if args[0] == "check-ref-format":
            return ""
        if args == ("worktree", "list", "--porcelain"):
            return f"worktree {repo}\nbare\n"
        self.fail(f"unexpected Git diagnostic: {args}")

    def compare(self, before, after):
        for name, value in (("before.json", before), ("after.json", after)):
            (self.repo / name).write_text(json.dumps(value))
        state.compare(argparse.Namespace(
            baseline=str(self.repo / "before.json"), actual=str(self.repo / "after.json"),
            allow_ref=[], allow_worktree=[],
        ))

    def test_immediate_chain_dangling_and_head_identity(self):
        with patch.object(state, "git", self.diagnostic):
            before = state.capture(self.args)
            self.assertEqual(before["refs"]["refs/fixture/chain"]["symbolic_target"], "refs/fixture/hop-a")
            self.assertEqual(before["refs"]["refs/fixture/dangling"],
                             {"oid": None, "symbolic_target": "refs/heads/unborn-a"})
            self.compare(before, state.capture(self.args))
            for name, target in (("refs/fixture/chain", "refs/fixture/hop-b"),
                                 ("refs/fixture/dangling", "refs/heads/unborn-b"),
                                 ("HEAD", "refs/fixture/hop-b")):
                with self.subTest(name=name):
                    original = (self.repo / name).read_text()
                    self.write(name, "ref: " + target + "\n")
                    with self.assertRaises(RuntimeError):
                        self.compare(before, state.capture(self.args))
                    self.write(name, original)
                    self.compare(before, state.capture(self.args))

    def test_loose_overrides_packed_and_packed_change_is_protected(self):
        self.write("packed-refs", "# pack-refs\n" + "b" * 40 + " refs/fixture/leaf\n"
                   + "c" * 40 + " refs/fixture/packed\n^" + "d" * 40 + "\n")
        with patch.object(state, "git", self.diagnostic):
            before = state.capture(self.args)
            self.assertEqual(before["refs"]["refs/fixture/leaf"]["oid"], "a" * 40)
            self.assertEqual(before["refs"]["refs/fixture/packed"]["oid"], "c" * 40)
            self.write("packed-refs", "e" * 40 + " refs/fixture/packed\n")
            with self.assertRaises(RuntimeError):
                self.compare(before, state.capture(self.args))

    def test_unsupported_backend_cannot_report_preservation(self):
        with patch.object(state, "git", return_value="reftable\n"):
            with self.assertRaisesRegex(RuntimeError, "files ref storage"):
                state.capture(self.args)


if __name__ == "__main__":
    unittest.main()
