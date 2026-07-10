#!/usr/bin/env python3
"""Static contract checks for the local GitHub CLI configuration Feature."""

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


def load_json(path: Path) -> dict:
    # devcontainer JSON files are JSONC; drop whole-line // comments before parsing.
    text = path.read_text(encoding="utf-8")
    lines = [line for line in text.splitlines() if not line.lstrip().startswith("//")]
    return json.loads("\n".join(lines))


def main() -> None:
    manifest = load_json(MANIFEST_PATH)
    devcontainer = load_json(DEVCONTAINER_PATH)

    assert manifest["id"] == "github-cli-config"
    assert manifest["dependsOn"] == {OFFICIAL_GITHUB_CLI_FEATURE: {}}
    assert manifest["installsAfter"] == ["ghcr.io/devcontainers/features/common-utils"]
    assert manifest["mounts"] == [MOUNT]
    assert manifest["postStartCommand"] == POST_START_COMMAND

    installer = INSTALLER_PATH.read_text(encoding="utf-8")
    # Both directory levels must be named: install -d applies ownership only to
    # the directories it is told to create, so naming only .config/gh leaves a
    # freshly created ~/.config root-owned.
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
