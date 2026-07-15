#!/usr/bin/env python3
"""Static contract checks for the local Codex Feature."""

import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[4]
FEATURE_DIR = ROOT / ".devcontainer/local-features/codex"
MANIFEST_PATH = FEATURE_DIR / "devcontainer-feature.json"
INSTALLER_PATH = FEATURE_DIR / "install.sh"
RUNTIME_TEST_PATH = FEATURE_DIR / "test/test-runtime.sh"

SECURITY_OPT = ["seccomp=unconfined", "apparmor=unconfined"]
RUNTIME_CAPABILITY_CANDIDATES = (
    "SYS_ADMIN",
    "SYS_CHROOT",
    "SETUID",
    "SETGID",
    "SYS_PTRACE",
)
EXPECTED_CAP_ADD: list[str] = []
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
    "executable hook copy": re.compile(
        r"(?:^|\$\(|\s)rsync\s+-rp\s+"
        r"--chown=\$\{_CONTAINER_USER\}:\$\{_CONTAINER_USER\}\s+"
        r"--chmod=D755,F755\s+bin/\.\s+"
        r"/home/\$\{_CONTAINER_USER\}/bin(?:\s|$)"
    ),
    "container-user re-execution environment": re.compile(
        r"(?:^|\$\()sudo\s+-iu\s+\"\$\{_CONTAINER_USER\}\"\s+env\s+"
        r"_CONTAINER_USER=\"\$\{_CONTAINER_USER\}\"\s+"
        r"\"\$installer_path\"(?:\s|$)"
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


def assert_runtime_user_contract(source: str) -> None:
    assert ".Config.User" not in source, (
        "runtime test must not infer containerUser from Docker image Config.User"
    )
    required_fragments = (
        '"$REPO_ROOT/.devcontainer/devcontainer.json"',
        're.fullmatch(r"\\$\\{localEnv:',
        "os.environ.get(environment_name, default)",
    )
    for fragment in required_fragments:
        assert fragment in source, f"runtime test missing containerUser resolver: {fragment}"
    assert source.count('--user "$IMAGE_USER"') >= 3, (
        "runtime test must use the resolved containerUser for identity, stat, and probes"
    )


def assert_runtime_volume_contract(source: str) -> None:
    assert "type=bind" not in source and "WRAPPER_DIR" not in source, (
        "runtime test must not use a daemon-host bind path for its wrapper"
    )
    required_fragments = (
        'docker volume create "$WRAPPER_VOLUME"',
        'docker volume rm -f "$WRAPPER_VOLUME"',
        'WRAPPER_MOUNT="type=volume,src=$WRAPPER_VOLUME,dst=/codex-runtime-test"',
        "initialize_wrapper_volume",
        "reset_wrapper_log",
        "read_wrapper_log",
        '--mount "$WRAPPER_MOUNT"',
    )
    for fragment in required_fragments:
        assert fragment in source, f"runtime test missing volume wrapper contract: {fragment}"


def assert_runtime_codex_path_contract(source: str) -> None:
    required_fragments = (
        'CODEX_PATH="$IMAGE_HOME/.local/bin/codex"',
        'test -x "$CODEX_PATH"',
        '--env "PATH=/codex-runtime-test:$IMAGE_HOME/.local/bin:$IMAGE_PATH"',
    )
    for fragment in required_fragments:
        assert fragment in source, f"runtime test missing Codex PATH contract: {fragment}"


def assert_runtime_capability_contract(source: str) -> None:
    candidates = " ".join(RUNTIME_CAPABILITY_CANDIDATES)
    assert f"CANDIDATES=({candidates})" in source, (
        "runtime test must retain the ordered five-capability candidate tuple"
    )
    assert "required=()" in source, (
        "runtime test must allow subtraction to derive an empty required set"
    )
    assert "printf 'REQUIRED_CAPABILITIES=%s\\n' \"$required_csv\"" in source, (
        "runtime test must print an empty machine-readable result when no capability is retained"
    )


def assert_runtime_build_status_contract(source: str) -> None:
    assert "if ! npx -y @devcontainers/cli@latest build" not in source, (
        "runtime test must not negate the build before capturing its exit status"
    )
    assert "else\n  status=$?" in source, (
        "runtime test must capture the failing build status at the start of the else branch"
    )


def assert_rejects(assertion, value: object) -> None:
    try:
        assertion(value)
    except AssertionError:
        return
    raise AssertionError("contract assertion accepted an invalid mutation")


def assert_equal(actual: object, expected: object) -> None:
    assert actual == expected, f"expected {expected!r}, got {actual!r}"


def test_installer_rejects_uid_zero_container_user() -> None:
    lines = executable_shell_lines(INSTALLER_PATH.read_text(encoding="utf-8"))
    uid_zero_guard = 'if [[ "$container_user_id" -eq 0 ]]'
    euid_branch = "if [[ $EUID -ne $container_user_id ]]"
    error = (
        '"Codex container user validation failed for \'${_CONTAINER_USER}\'. '
        "Codex cannot safely install Bubblewrap or the CLI as the intended user. "
        "Set _CONTAINER_USER to an existing non-root account and rebuild the container. "
        "id said: '${_CONTAINER_USER}' resolved to UID $container_user_id\" >&2"
    )

    assert uid_zero_guard in lines, "installer does not reject a UID-0 container user"
    assert lines.index(uid_zero_guard) < lines.index(euid_branch), (
        "UID-0 rejection must precede the EUID branch"
    )
    assert any(error in line for line in lines), (
        "UID-0 rejection lacks the required ordered diagnostic"
    )


def test_installer_command_mutations() -> None:
    commands = [
        "DEBIAN_FRONTEND=noninteractive apt-get install -y bubblewrap",
        "chown root:root /usr/bin/bwrap && chmod 4755 /usr/bin/bwrap",
        "metadata=\"$(stat -c '%U:%G %a' /usr/bin/bwrap)\"",
        "rsync -rp --chown=${_CONTAINER_USER}:${_CONTAINER_USER} "
        "--chmod=D755,F755 bin/. /home/${_CONTAINER_USER}/bin",
        'sudo -iu "${_CONTAINER_USER}" env '
        '_CONTAINER_USER="${_CONTAINER_USER}" "$installer_path"',
    ]
    comments = [f"# {command}" for command in commands]
    valid_installer = "\n".join(commands + comments)
    assert_installer_commands(valid_installer)

    mutations = {
        "apt-get install": commands[0],
        "chown": "chown root:root /usr/bin/bwrap && ",
        "chmod": " && chmod 4755 /usr/bin/bwrap",
        "stat": commands[2],
        "executable hook copy": commands[3],
        "container-user re-execution environment": (
            'env _CONTAINER_USER="${_CONTAINER_USER}" '
        ),
    }
    for command in mutations.values():
        mutated = valid_installer.replace(command, "", 1)
        assert_rejects(assert_installer_commands, mutated)


def test_security_option_path_mutation() -> None:
    assert_rejects(
        assert_security_options,
        ["seccomp=/workspaces/seccomp.json", "apparmor=unconfined"],
    )


def test_runtime_user_contract_mutations() -> None:
    valid_source = "\n".join(
        (
            'config="$REPO_ROOT/.devcontainer/devcontainer.json"',
            're.fullmatch(r"\\$\\{localEnv:", configured_user)',
            "os.environ.get(environment_name, default)",
            'docker run --user "$IMAGE_USER"',
            'docker run --user "$IMAGE_USER"',
            'docker run --user "$IMAGE_USER"',
        )
    )
    assert_runtime_user_contract(valid_source)
    for fragment in (
        '"$REPO_ROOT/.devcontainer/devcontainer.json"',
        're.fullmatch(r"\\$\\{localEnv:',
        "os.environ.get(environment_name, default)",
        'docker run --user "$IMAGE_USER"',
    ):
        assert_rejects(assert_runtime_user_contract, valid_source.replace(fragment, ""))
    assert_rejects(assert_runtime_user_contract, valid_source + "\n.Config.User")


def test_runtime_volume_contract_mutations() -> None:
    valid_source = "\n".join(
        (
            'docker volume create "$WRAPPER_VOLUME"',
            'docker volume rm -f "$WRAPPER_VOLUME"',
            'WRAPPER_MOUNT="type=volume,src=$WRAPPER_VOLUME,dst=/codex-runtime-test"',
            "initialize_wrapper_volume",
            "reset_wrapper_log",
            "read_wrapper_log",
            'docker run --mount "$WRAPPER_MOUNT"',
        )
    )
    assert_runtime_volume_contract(valid_source)
    for fragment in valid_source.splitlines():
        assert_rejects(assert_runtime_volume_contract, valid_source.replace(fragment, ""))
    assert_rejects(
        assert_runtime_volume_contract,
        valid_source + "\n--mount type=bind,src=$WRAPPER_DIR,dst=/codex-runtime-test",
    )


def test_runtime_codex_path_contract_mutations() -> None:
    valid_source = "\n".join(
        (
            'CODEX_PATH="$IMAGE_HOME/.local/bin/codex"',
            'docker run "$IMAGE" test -x "$CODEX_PATH"',
            '--env "PATH=/codex-runtime-test:$IMAGE_HOME/.local/bin:$IMAGE_PATH"',
        )
    )
    assert_runtime_codex_path_contract(valid_source)
    for fragment in valid_source.splitlines():
        assert_rejects(
            assert_runtime_codex_path_contract,
            valid_source.replace(fragment, ""),
        )


def test_runtime_capability_contract_mutations() -> None:
    candidates = " ".join(RUNTIME_CAPABILITY_CANDIDATES)
    valid_source = "\n".join(
        (
            f"CANDIDATES=({candidates})",
            "required=()",
            "printf 'REQUIRED_CAPABILITIES=%s\\n' \"$required_csv\"",
        )
    )
    assert_runtime_capability_contract(valid_source)
    for fragment in valid_source.splitlines():
        assert_rejects(
            assert_runtime_capability_contract,
            valid_source.replace(fragment, ""),
        )


def test_runtime_build_status_contract_mutations() -> None:
    valid_source = "if npx -y @devcontainers/cli@latest build; then\n  :\nelse\n  status=$?"
    assert_runtime_build_status_contract(valid_source)
    assert_rejects(
        assert_runtime_build_status_contract,
        valid_source.replace("if npx", "if ! npx"),
    )
    assert_rejects(
        assert_runtime_build_status_contract,
        valid_source.replace("else\n  status=$?", "else\n  :\n  status=$?"),
    )


def main() -> None:
    test_installer_rejects_uid_zero_container_user()
    test_installer_command_mutations()
    test_security_option_path_mutation()
    test_runtime_user_contract_mutations()
    test_runtime_volume_contract_mutations()
    test_runtime_codex_path_contract_mutations()
    test_runtime_capability_contract_mutations()
    test_runtime_build_status_contract_mutations()

    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    installer = INSTALLER_PATH.read_text(encoding="utf-8")
    runtime_test = RUNTIME_TEST_PATH.read_text(encoding="utf-8")

    failures: list[str] = []
    checks = [
        ("securityOpt", lambda: assert_security_options(manifest.get("securityOpt"))),
        ("capAdd", lambda: assert_equal(manifest.get("capAdd"), EXPECTED_CAP_ADD)),
        (
            "postCreateCommand",
            lambda: assert_equal(manifest.get("postCreateCommand"), POST_CREATE_COMMAND),
        ),
        ("installer commands", lambda: assert_installer_commands(installer)),
        (
            "runtime containerUser",
            lambda: assert_runtime_user_contract(runtime_test),
        ),
        (
            "runtime wrapper volume",
            lambda: assert_runtime_volume_contract(runtime_test),
        ),
        (
            "runtime Codex PATH",
            lambda: assert_runtime_codex_path_contract(runtime_test),
        ),
        (
            "runtime capabilities",
            lambda: assert_runtime_capability_contract(runtime_test),
        ),
        (
            "runtime build status",
            lambda: assert_runtime_build_status_contract(runtime_test),
        ),
    ]
    for description, check in checks:
        try:
            check()
        except (AssertionError, TypeError) as error:
            failures.append(f"{description}: {error or 'contract mismatch'}")

    assert not failures, "\n".join(failures)


if __name__ == "__main__":
    main()
