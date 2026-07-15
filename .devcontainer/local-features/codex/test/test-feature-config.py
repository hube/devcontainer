#!/usr/bin/env python3
"""Static contract checks for the local Codex Feature."""

import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[4]
FEATURE_DIR = ROOT / ".devcontainer/local-features/codex"
MANIFEST_PATH = FEATURE_DIR / "devcontainer-feature.json"
INSTALLER_PATH = FEATURE_DIR / "install.sh"

SECURITY_OPT = ["seccomp=unconfined", "apparmor=unconfined"]
CAPABILITY_CANDIDATES = [
    "SYS_ADMIN",
    "SYS_CHROOT",
    "SETUID",
    "SETGID",
    "SYS_PTRACE",
]
POST_CREATE_COMMAND = "~/bin/devcontainer-feature/codex/postCreateScript.sh"

REQUIRED_INSTALLER_COMMANDS = {
    "Bubblewrap package installation": re.compile(
        r"(?:^|&&\s+)(?:DEBIAN_FRONTEND=noninteractive\s+)?"
        r"apt-get\s+install\s+-y\s+bubblewrap(?:\s|$)"
    ),
    "Bubblewrap ownership": re.compile(
        r"(?:^|&&\s+)chown\s+root:root\s+/usr/bin/bwrap(?:\s|$)"
    ),
    "Bubblewrap mode": re.compile(
        r"(?:^|&&\s+)chmod\s+4755\s+/usr/bin/bwrap(?:\s|$)"
    ),
    "Bubblewrap metadata verification": re.compile(
        r"(?:^|\$\()stat\s+-c\s+['\"]%U:%G %a['\"]\s+/usr/bin/bwrap(?:\s|\)|$)"
    ),
}


def executable_shell_lines(source: str) -> list[str]:
    """Return normalized logical lines, excluding shell comments."""
    uncommented = "\n".join(
        line for line in source.splitlines() if not line.lstrip().startswith("#")
    )
    logical_source = re.sub(r"\\\s*\n\s*", " ", uncommented)
    return [re.sub(r"\s+", " ", line.strip()) for line in logical_source.splitlines()]


def assert_installer_commands(source: str) -> None:
    lines = executable_shell_lines(source)
    for description, pattern in REQUIRED_INSTALLER_COMMANDS.items():
        assert any(pattern.search(line) for line in lines), (
            f"missing executable command for {description}"
        )


def assert_security_options(options: object) -> None:
    assert options == SECURITY_OPT
    for option in options:
        value = option.partition("=")[2]
        assert value and not Path(value).is_absolute(), (
            f"securityOpt must use a named profile, not a filesystem path: {option}"
        )


def assert_rejects(assertion, value: object) -> None:
    try:
        assertion(value)
    except AssertionError:
        return
    raise AssertionError("contract assertion accepted an invalid mutation")


def assert_equal(actual: object, expected: object) -> None:
    assert actual == expected, f"expected {expected!r}, got {actual!r}"


def test_installer_command_mutations() -> None:
    commands = [
        "DEBIAN_FRONTEND=noninteractive apt-get install -y bubblewrap",
        "chown root:root /usr/bin/bwrap && chmod 4755 /usr/bin/bwrap",
        "metadata=\"$(stat -c '%U:%G %a' /usr/bin/bwrap)\"",
    ]
    comments = [f"# {command}" for command in commands]
    valid_installer = "\n".join(commands + comments)
    assert_installer_commands(valid_installer)

    mutations = {
        "apt-get install": commands[0],
        "chown": "chown root:root /usr/bin/bwrap && ",
        "chmod": " && chmod 4755 /usr/bin/bwrap",
        "stat": commands[2],
    }
    for command in mutations.values():
        mutated = valid_installer.replace(command, "", 1)
        assert_rejects(assert_installer_commands, mutated)


def test_security_option_path_mutation() -> None:
    assert_rejects(
        assert_security_options,
        ["seccomp=/workspaces/seccomp.json", "apparmor=unconfined"],
    )


def main() -> None:
    test_installer_command_mutations()
    test_security_option_path_mutation()

    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    installer = INSTALLER_PATH.read_text(encoding="utf-8")

    failures: list[str] = []
    checks = [
        ("securityOpt", lambda: assert_security_options(manifest.get("securityOpt"))),
        ("capAdd", lambda: assert_equal(manifest.get("capAdd"), CAPABILITY_CANDIDATES)),
        (
            "postCreateCommand",
            lambda: assert_equal(manifest.get("postCreateCommand"), POST_CREATE_COMMAND),
        ),
        ("installer commands", lambda: assert_installer_commands(installer)),
    ]
    for description, check in checks:
        try:
            check()
        except (AssertionError, TypeError) as error:
            failures.append(f"{description}: {error or 'contract mismatch'}")

    assert not failures, "\n".join(failures)


if __name__ == "__main__":
    main()
