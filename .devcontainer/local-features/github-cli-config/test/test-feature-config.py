#!/usr/bin/env python3
"""Static contract checks for the local GitHub CLI configuration feature."""

import json
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[4]
FEATURE_DIR = ROOT / ".devcontainer/local-features/github-cli-config"
MANIFEST_PATH = FEATURE_DIR / "devcontainer-feature.json"
INSTALLER_PATH = FEATURE_DIR / "install.sh"
DEVCONTAINER_PATH = ROOT / ".devcontainer/devcontainer.json"

OFFICIAL_GITHUB_CLI_FEATURE = "ghcr.io/devcontainers/features/github-cli:1"
LOCAL_GITHUB_CLI_CONFIG_FEATURE = "./local-features/github-cli-config"
MOUNT = {
    "type": "volume",
    "source": "github-cli-config-${devcontainerId}",
    "target": "/home/${localEnv:USERNAME:devcontainer}/.config/gh",
}
POST_START_COMMAND = "~/bin/devcontainer-feature/github-cli-config/postStartScript.sh"


def strip_jsonc_comments(text: str) -> str:
    result: list[str] = []
    index = 0
    in_string = False
    escaped = False

    while index < len(text):
        character = text[index]
        if in_string:
            result.append(character)
            if escaped:
                escaped = False
            elif character == "\\":
                escaped = True
            elif character == '"':
                in_string = False
            index += 1
            continue

        if character == '"':
            in_string = True
            result.append(character)
            index += 1
        elif text.startswith("//", index):
            index += 2
            while index < len(text) and text[index] not in "\r\n":
                index += 1
        elif text.startswith("/*", index):
            index += 2
            while index < len(text) and not text.startswith("*/", index):
                if text[index] in "\r\n":
                    result.append(text[index])
                index += 1
            if index == len(text):
                raise ValueError("Unterminated block comment in JSONC input")
            index += 2
        else:
            result.append(character)
            index += 1

    return "".join(result)


def strip_jsonc_trailing_commas(text: str) -> str:
    result: list[str] = []
    index = 0
    in_string = False
    escaped = False

    while index < len(text):
        character = text[index]
        if in_string:
            result.append(character)
            if escaped:
                escaped = False
            elif character == "\\":
                escaped = True
            elif character == '"':
                in_string = False
            index += 1
            continue

        if character == '"':
            in_string = True
        elif character == ",":
            next_index = index + 1
            while next_index < len(text) and text[next_index].isspace():
                next_index += 1
            if next_index < len(text) and text[next_index] in "}]":
                index += 1
                continue

        result.append(character)
        index += 1

    return "".join(result)


def load_jsonc(text: str) -> dict:
    return json.loads(strip_jsonc_trailing_commas(strip_jsonc_comments(text)))


def load_json(path: Path) -> dict:
    return load_jsonc(path.read_text(encoding="utf-8"))


def test_load_jsonc_supports_comments_and_trailing_commas() -> None:
    source = r'''{
      // whole-line comment
      "url": "https://example.test/a//b", /* block comment */
      "marker": ",}",
      "bracket": ",]",
      "items": ["/* literal */",], // inline comment
    }'''
    assert load_jsonc(source) == {
        "url": "https://example.test/a//b",
        "marker": ",}",
        "bracket": ",]",
        "items": ["/* literal */"],
    }


def main() -> None:
    test_load_jsonc_supports_comments_and_trailing_commas()
    manifest = load_json(MANIFEST_PATH)
    devcontainer = load_json(DEVCONTAINER_PATH)
    assert list(devcontainer).index("containerEnv") < list(devcontainer).index("remoteEnv")

    assert manifest["id"] == "github-cli-config"
    assert manifest["dependsOn"] == {OFFICIAL_GITHUB_CLI_FEATURE: {}}
    assert manifest["installsAfter"] == ["ghcr.io/devcontainers/features/common-utils"]
    assert manifest["mounts"] == [MOUNT]
    assert manifest["postStartCommand"] == POST_START_COMMAND

    installer = INSTALLER_PATH.read_text(encoding="utf-8")
    assert (
        'install -d -o "${_CONTAINER_USER}" -g "${_CONTAINER_USER}" -m 0755'
        ' "$user_home/.config" "$user_home/.config/gh"'
    ) in installer

    features = devcontainer["features"]
    assert OFFICIAL_GITHUB_CLI_FEATURE in features
    assert LOCAL_GITHUB_CLI_CONFIG_FEATURE in features
    assert list(features).index(LOCAL_GITHUB_CLI_CONFIG_FEATURE) == list(features).index("./local-features/direnv") + 1
    assert list(features).index(LOCAL_GITHUB_CLI_CONFIG_FEATURE) + 1 == list(features).index("./local-features/ssh")

    assert devcontainer["remoteEnv"]["GH_TOKEN"] == "${localEnv:GH_TOKEN}"
    assert devcontainer["remoteEnv"]["GITHUB_TOKEN"] == "${localEnv:GITHUB_TOKEN}"
    assert set(devcontainer["secrets"]) >= {"GH_TOKEN", "GITHUB_TOKEN"}
    assert "TZ" not in devcontainer["remoteEnv"]
    assert devcontainer["containerEnv"]["TZ"] == "${localEnv:TZ:America/Los_Angeles}"

    codex = load_json(ROOT / ".devcontainer/local-features/codex/devcontainer-feature.json")
    assert "shell_environment_policy" not in codex

    syntax = subprocess.run(
        ["bash", "-n", str(INSTALLER_PATH)], check=False, capture_output=True, text=True
    )
    assert syntax.returncode == 0, syntax.stderr


if __name__ == "__main__":
    main()
