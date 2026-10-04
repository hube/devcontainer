#!/usr/bin/env python3
"""Static contract checks for the local Codex Feature."""

import copy
import json
import re
import tomllib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[4]
FEATURE_DIR = ROOT / ".devcontainer/local-features/codex"
MANIFEST_PATH = FEATURE_DIR / "devcontainer-feature.json"
INSTALLER_PATH = FEATURE_DIR / "install.sh"
RUNTIME_TEST_PATH = FEATURE_DIR / "test/test-runtime.sh"
CONFIG_PATH = FEATURE_DIR / "home/.codex/config.toml"
CONSUMER_PATH = ROOT / ".devcontainer/devcontainer.json"

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


def assert_runtime_desktop_contract(source: str) -> None:
    info = "docker info --format '{{.OperatingSystem}}'"
    check = '[[ "$DOCKER_OPERATING_SYSTEM" != "Docker Desktop" ]]'
    build = "if npx -y @devcontainers/cli@latest build"
    for fragment in (info, check, build):
        assert fragment in source, f"runtime test missing Docker Desktop gate: {fragment}"
    assert source.index(info) < source.index(check) < source.index(build), (
        "runtime test must verify Docker Desktop identity before building or deriving capabilities"
    )


def assert_runtime_control_contract(source: str) -> None:
    run = 'run_probe control-default-security "${control_args[@]}"'
    restriction = 'CONTROL_RESTRICTION="bwrap: pivot_root: Operation not permitted"'
    check = (
        '[[ -z "$PROBE_BWRAP_LOG" || '
        '"$PROBE_OUTPUT" != *"$CONTROL_RESTRICTION"* ]]'
    )
    treatment = 'run_probe treatment-full-candidates "${full_runtime_args[@]}"'
    for fragment in (run, restriction, check, "control_evidence=", treatment):
        assert fragment in source, f"runtime test missing valid-control contract: {fragment}"
    assert source.index(run) < source.index(check) < source.index(treatment), (
        "runtime test must validate control output and wrapper evidence before treatment"
    )


def assert_runtime_omission_contract(source: str) -> None:
    run = 'run_probe "omit-$omitted" "${omission_args[@]}"'
    saved = (
        "omission_status=$PROBE_STATUS",
        "omission_output=$PROBE_OUTPUT",
        "omission_bwrap_log=$PROBE_BWRAP_LOG",
    )
    check = 'if [[ -z "$omission_bwrap_log" ]]; then'
    evidence = "omission_evidence="
    restore = 'run_probe "restore-after-$omitted" "${full_runtime_args[@]}"'
    for fragment in (run, *saved, check, evidence, restore):
        assert fragment in source, f"runtime test missing omission evidence contract: {fragment}"
    positions = [source.index(fragment) for fragment in (run, *saved, check, restore)]
    assert positions == sorted(positions), (
        "runtime test must save and validate omission evidence before restoration overwrites it"
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


def test_runtime_desktop_contract_mutations() -> None:
    valid_source = "\n".join(
        (
            "DOCKER_OPERATING_SYSTEM=\"$(docker info --format '{{.OperatingSystem}}')\"",
            '[[ "$DOCKER_OPERATING_SYSTEM" != "Docker Desktop" ]]',
            "if npx -y @devcontainers/cli@latest build; then",
        )
    )
    assert_runtime_desktop_contract(valid_source)
    for fragment in valid_source.splitlines():
        assert_rejects(
            assert_runtime_desktop_contract,
            valid_source.replace(fragment, ""),
        )


def test_runtime_control_contract_mutations() -> None:
    valid_source = "\n".join(
        (
            'CONTROL_RESTRICTION="bwrap: pivot_root: Operation not permitted"',
            'run_probe control-default-security "${control_args[@]}"',
            '[[ -z "$PROBE_BWRAP_LOG" || "$PROBE_OUTPUT" != *"$CONTROL_RESTRICTION"* ]]',
            "control_evidence=output-and-log",
            'run_probe treatment-full-candidates "${full_runtime_args[@]}"',
        )
    )
    assert_runtime_control_contract(valid_source)
    for fragment in valid_source.splitlines():
        assert_rejects(
            assert_runtime_control_contract,
            valid_source.replace(fragment, ""),
        )


def test_runtime_omission_contract_mutations() -> None:
    valid_source = "\n".join(
        (
            'run_probe "omit-$omitted" "${omission_args[@]}"',
            "omission_status=$PROBE_STATUS",
            "omission_output=$PROBE_OUTPUT",
            "omission_bwrap_log=$PROBE_BWRAP_LOG",
            'if [[ -z "$omission_bwrap_log" ]]; then',
            "omission_evidence=output-and-log",
            'run_probe "restore-after-$omitted" "${full_runtime_args[@]}"',
        )
    )
    assert_runtime_omission_contract(valid_source)
    for fragment in valid_source.splitlines():
        assert_rejects(
            assert_runtime_omission_contract,
            valid_source.replace(fragment, ""),
        )
    assert_rejects(
        assert_runtime_omission_contract,
        valid_source.replace(
            'if [[ -z "$omission_bwrap_log" ]]; then\nomission_evidence=output-and-log',
            "omission_evidence=output-and-log",
        )
        + '\nif [[ -z "$omission_bwrap_log" ]]; then',
    )


def assert_recovery_inputs(config: dict, manifest: dict, consumer: dict) -> None:
    """Check repository inputs only; no Codex, Docker, or host-mount stub."""
    assert config.get("approvals_reviewer") == "auto_review", (
        "feature default must select automatic review; effective policy needs a live probe"
    )
    home = "/home/${localEnv:USERNAME:devcontainer}"
    mounts = manifest.get("mounts", [])
    assert any(
        mount.get("type") == "volume"
        and mount.get("source") == "codex-code-config-${devcontainerId}"
        and mount.get("target") == f"{home}/.codex"
        for mount in mounts
    ), "missing persistent Codex volume input"
    assert any(
        mount.get("type") == "bind"
        and mount.get("source") == "${localEnv:HOME}/.claude/CLAUDE.md"
        and mount.get("target") == f"{home}/.codex/AGENTS.md"
        for mount in mounts
    ), "missing shared always-on guidance mount input"
    assert any(
        mount.get("type") == "bind,readonly"
        and mount.get("source")
        and mount.get("target") == f"{home}/.agents/instructions"
        for mount in consumer.get("mounts", [])
    ), "missing read-only consumer bulk guidance mount input"


def test_recovery_input_mutations(config: dict, manifest: dict, consumer: dict) -> None:
    """Mutate actual feature/consumer inputs; runtime policy is not simulated."""
    assert_recovery_inputs(config, manifest, consumer)
    changed_config = dict(config, approvals_reviewer="user")
    assert_rejects(
        lambda value: assert_recovery_inputs(value, manifest, consumer), changed_config
    )
    for mount in manifest["mounts"]:
        if mount["target"].endswith(("/.codex", "/.codex/AGENTS.md")):
            changed = copy.deepcopy(manifest)
            changed["mounts"].remove(mount)
            assert_rejects(
                lambda value: assert_recovery_inputs(config, value, consumer), changed
            )
    for field, value in (("type", "bind"), ("source", ""), ("target", "/wrong")):
        changed = copy.deepcopy(consumer)
        for mount in changed["mounts"]:
            if mount["target"].endswith("/.agents/instructions"):
                mount[field] = value
        assert changed != consumer, "mutation did not change the consumer fixture"
        assert_rejects(
            lambda value: assert_recovery_inputs(config, manifest, value), changed
        )


def assert_retrieval_inputs(consumer: dict, ssh_manifest: dict, hook: str) -> None:
    """Check our selected SSH wiring; no transport, agent, or Docker stub."""
    failures: list[str] = []
    if "./local-features/ssh" not in consumer.get("features", {}):
        failures.append(
            "Consumer omits its SSH transport Feature. "
            "Input acceptance cannot establish host-agent wiring. "
            "Restore ./local-features/ssh in the consumer features."
        )
    socket = ssh_manifest.get("containerEnv", {}).get("SSH_AUTH_SOCK")
    if not socket or not any(
        mount.get("type") == "bind"
        and mount.get("source") == socket
        and mount.get("target") == socket
        for mount in ssh_manifest.get("mounts", [])
    ):
        failures.append(
            "SSH_AUTH_SOCK does not name the declared host-agent socket mount. "
            "SSH retrieval would select an unmounted socket. "
            "Make containerEnv.SSH_AUTH_SOCK match the socket bind source and target."
        )
    known_hosts = (
        "/home/${localEnv:USERNAME:devcontainer}/host-readonly/home/.ssh/known_hosts"
    )
    if not any(
        mount.get("type") == "bind,readonly"
        and mount.get("source") == "${localEnv:HOME}/.ssh/known_hosts"
        and mount.get("target") == known_hosts
        for mount in ssh_manifest.get("mounts", [])
    ):
        failures.append(
            "SSH known-hosts input lacks its configured read-only mount. "
            "The hook cannot receive the host trust input. "
            "Restore the host known_hosts bind at the hook's configured source path."
        )
    if ssh_manifest.get("postStartCommand") != (
        "~/bin/devcontainer-feature/ssh/postStartScript.sh"
    ):
        failures.append(
            "SSH Feature does not invoke its configured startup hook. "
            "The checked known-hosts copy would not run at container startup. "
            "Restore postStartCommand for the SSH postStartScript.sh."
        )
    if "cp ~/host-readonly/home/.ssh/known_hosts ~/.ssh/known_hosts" not in (
        executable_shell_lines(hook)
    ):
        failures.append(
            "SSH hook lacks the executable known-hosts copy. "
            "A client without known_hosts cannot receive the configured host trust input. "
            "Restore the copy from ~/host-readonly/home/.ssh/known_hosts."
        )
    assert not failures, "\n".join(failures)


def test_retrieval_input_mutations(consumer: dict, manifest: dict, hook: str) -> None:
    assert_retrieval_inputs(consumer, manifest, hook)
    changed_consumer = copy.deepcopy(consumer)
    del changed_consumer["features"]["./local-features/ssh"]
    assert changed_consumer != consumer
    assert_rejects(
        lambda value: assert_retrieval_inputs(value, manifest, hook), changed_consumer
    )
    changed_manifest = copy.deepcopy(manifest)
    changed_manifest["containerEnv"]["SSH_AUTH_SOCK"] = "/wrong/socket"
    assert changed_manifest != manifest
    assert_rejects(
        lambda value: assert_retrieval_inputs(consumer, value, hook), changed_manifest
    )
    changed_manifest = copy.deepcopy(manifest)
    del changed_manifest["postStartCommand"]
    assert changed_manifest != manifest
    assert_rejects(
        lambda value: assert_retrieval_inputs(consumer, value, hook), changed_manifest
    )
    for mount in manifest["mounts"]:
        changed_manifest = copy.deepcopy(manifest)
        changed_manifest["mounts"].remove(mount)
        assert changed_manifest != manifest
        assert_rejects(
            lambda value: assert_retrieval_inputs(consumer, value, hook), changed_manifest
        )
    copy_command = "cp ~/host-readonly/home/.ssh/known_hosts ~/.ssh/known_hosts"
    changed_hook = hook.replace(copy_command, "# " + copy_command)
    assert changed_hook != hook
    assert_rejects(
        lambda value: assert_retrieval_inputs(consumer, manifest, value), changed_hook
    )


def assert_task_check_inputs(consumer: dict, node_provider: dict) -> None:
    """Check this consumer's interpreter dependency; no Node or Docker stub."""
    failures: list[str] = []
    if "./local-features/git-commit-attribution" not in consumer.get("features", {}):
        failures.append(
            "Consumer omits the Feature supplying its declared Node dependency. "
            "Task-check input acceptance cannot establish an interpreter provider. "
            "Restore ./local-features/git-commit-attribution or revise the checked provider."
        )
    if "ghcr.io/devcontainers/features/node:2" not in node_provider.get("dependsOn", {}):
        failures.append(
            "The selected interpreter provider omits its Node dependency. "
            "Node task checks cannot rely on this consumer's dependency graph. "
            "Restore the Node dependsOn entry in git-commit-attribution."
        )
    assert not failures, "\n".join(failures)


def test_task_check_input_mutations(consumer: dict, node_provider: dict) -> None:
    assert_task_check_inputs(consumer, node_provider)
    changed_consumer = copy.deepcopy(consumer)
    del changed_consumer["features"]["./local-features/git-commit-attribution"]
    assert changed_consumer != consumer
    assert_rejects(
        lambda value: assert_task_check_inputs(value, node_provider), changed_consumer
    )
    changed_provider = copy.deepcopy(node_provider)
    del changed_provider["dependsOn"]["ghcr.io/devcontainers/features/node:2"]
    assert changed_provider != node_provider
    assert_rejects(
        lambda value: assert_task_check_inputs(consumer, value), changed_provider
    )
    try:
        assert_task_check_inputs(changed_consumer, changed_provider)
    except AssertionError as error:
        assert "Consumer omits" in str(error) and "provider omits" in str(error), (
            "input validation must report both missing interpreter inputs"
        )
    else:
        raise AssertionError("combined missing-input mutation was accepted")


def main() -> None:
    test_installer_rejects_uid_zero_container_user()
    test_installer_command_mutations()
    test_security_option_path_mutation()
    test_runtime_user_contract_mutations()
    test_runtime_volume_contract_mutations()
    test_runtime_codex_path_contract_mutations()
    test_runtime_capability_contract_mutations()
    test_runtime_build_status_contract_mutations()
    test_runtime_desktop_contract_mutations()
    test_runtime_control_contract_mutations()
    test_runtime_omission_contract_mutations()

    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    config = tomllib.loads(CONFIG_PATH.read_text(encoding="utf-8"))
    # This consumer uses full-line JSONC comments; retain URLs and values intact.
    consumer_source = "\n".join(
        line for line in CONSUMER_PATH.read_text(encoding="utf-8").splitlines()
        if not line.lstrip().startswith("//")
    )
    consumer = json.loads(consumer_source)
    test_recovery_input_mutations(config, manifest, consumer)
    ssh_dir = ROOT / ".devcontainer/local-features/ssh"
    ssh_source = "\n".join(
        line for line in (ssh_dir / "devcontainer-feature.json").read_text().splitlines()
        if not line.lstrip().startswith("//")
    )
    ssh_manifest = json.loads(ssh_source)
    ssh_hook = (ssh_dir / "bin/devcontainer-feature/ssh/postStartScript.sh").read_text()
    test_retrieval_input_mutations(consumer, ssh_manifest, ssh_hook)
    provider_path = (
        ROOT / ".devcontainer/local-features/git-commit-attribution/devcontainer-feature.json"
    )
    provider_source = "\n".join(
        line for line in provider_path.read_text().splitlines()
        if not line.lstrip().startswith("//")
    )
    test_task_check_input_mutations(consumer, json.loads(provider_source))
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
        (
            "runtime Docker Desktop identity",
            lambda: assert_runtime_desktop_contract(runtime_test),
        ),
        (
            "runtime default-security control",
            lambda: assert_runtime_control_contract(runtime_test),
        ),
        (
            "runtime omission evidence",
            lambda: assert_runtime_omission_contract(runtime_test),
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
