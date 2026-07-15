#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
NOTES="$ROOT/.devcontainer/local-features/codex/NOTES.md"
README="$ROOT/README.md"
MANIFEST="$ROOT/.devcontainer/local-features/codex/devcontainer-feature.json"
CONSUMER_TEST="$ROOT/.devcontainer/local-features/codex/test/test-image-consumer.sh"

check_documentation() {
  python3 - "$NOTES" "$README" "$MANIFEST" "$CONSUMER_TEST" <<'PY'
import json
import sys
from pathlib import Path

notes_path, readme_path, manifest_path, consumer_path = map(Path, sys.argv[1:])
notes = notes_path.read_text(encoding="utf-8")
normalized_notes = " ".join(notes.split())
readme = readme_path.read_text(encoding="utf-8")
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
consumer = consumer_path.read_text(encoding="utf-8")

required_notes = {
    "Docker Desktop support": "Docker Desktop in Linux-container mode",
    "seccomp option": "`seccomp=unconfined`",
    "AppArmor option": "`apparmor=unconfined`",
    "system Bubblewrap path": "`/usr/bin/bwrap`",
    "Bubblewrap ownership and mode": "`root:root` with mode `4755`",
    "system Bubblewrap selection": "instead of Codex's bundled fallback",
    "relaxed outer boundary": "relaxed outer Docker boundary",
    "Codex inner sandbox": "Codex's inner sandbox",
    "container-wide exposure": "container-wide",
    "non-Codex consequence": "non-Codex processes",
    "creation failure remedy": "container creation fails",
    "health failure remedy": "post-create health check fails",
    "consumer security option conflict": "additional `securityOpt` entries",
    "unsupported conflict": "unsupported",
    "retirement signal": "`bwrap: pivot_root: Operation not permitted`",
    "local acceptance": "test-image-consumer.sh codex-runtime-test:",
    "post-publication acceptance": "test-image-consumer.sh ghcr.io/hube/devcontainer:latest",
    "empty capability result": "does not add Docker capabilities",
}
failures = [
    f"NOTES missing {label}: {text}"
    for label, text in required_notes.items()
    if text not in normalized_notes
]
for capability in manifest.get("capAdd", []):
    if f"`{capability}`" not in normalized_notes:
        failures.append(f"NOTES missing final capability: {capability}")

notes_link = ".devcontainer/local-features/codex/NOTES.md"
if notes_link not in readme:
    failures.append(f"README missing Codex NOTES link: {notes_link}")
if "Codex" not in readme:
    failures.append("README missing high-level Codex summary")

for forbidden in (
    "seccomp=unconfined",
    "apparmor=unconfined",
    "SYS_ADMIN",
    "SYS_CHROOT",
    "SETUID",
    "SETGID",
    "SYS_PTRACE",
    "/usr/bin/bwrap",
    "capAdd",
):
    if forbidden in readme:
        failures.append(f"README duplicates detailed runtime/security material: {forbidden}")

required_consumer = {
    "nested-container detection": "if [[ -e /.dockerenv ]]",
    "current-container mount inspection": 'docker inspect "$(hostname)"',
    "outer workspace destination": 'mktemp -d "$OUTER_WORKSPACE_DESTINATION/',
    "Docker path wrapper": 'DOCKER_PATH="$HARNESS_ROOT/docker"',
    "bind-source translation": 'translate_bind_source() {',
    "Dev Container Docker override": '--docker-path "$DOCKER_PATH"',
    "host HOME substitution": 'HOME="$CLI_HOME" npm_config_cache="$NPM_CACHE"',
    "direct-host Docker fallback": 'else\n  WORKSPACE="$(mktemp -d)"\n  DOCKER_PATH="docker"\nfi',
    "direct-host temporary workspace": 'WORKSPACE="$(mktemp -d)"',
    "stable fixture label": 'FIXTURE_LABEL="codex.image-consumer=$FIXTURE_TOKEN"',
    "deterministic fixture volume suffix": 'DEVCONTAINER_ID=',
    "early fixture volume discovery": 'discover_fixture_volumes() {',
    "consistent up labels": 'run_devcontainer up',
    "consistent exec labels": 'run_devcontainer exec',
    "UID rewrite bypass": 'run_devcontainer up --update-remote-user-uid-default never',
    "Docker wrapper preflight": 'preflight_docker() {',
    "captured wrapper preflight": 'preflight_output="$(preflight_docker 2>&1)"',
}
for label, text in required_consumer.items():
    if text not in consumer:
        failures.append(f"consumer test missing {label}: {text}")

for forbidden in ('"features"', '"runArgs"', '"mounts"', '"securityOpt"', '"capAdd"'):
    if forbidden in consumer:
        failures.append(f"consumer test adds forbidden config material: {forbidden}")

if failures:
    raise SystemExit("Codex documentation contract failed:\n- " + "\n- ".join(failures))
PY
}

assert_mutation_rejected() {
  local label="$1"
  local target="$2"
  local needle="$3"
  local replacement="${4:-}"
  local temporary backup output status
  temporary="$(mktemp)"
  backup="$(mktemp)"
  cp "$target" "$backup"
  trap 'cp "$backup" "$target"; rm -f "$temporary" "$backup"' RETURN
  python3 - "$target" "$temporary" "$needle" "$replacement" <<'PY'
import sys
from pathlib import Path

source, destination = map(Path, sys.argv[1:3])
needle, replacement = sys.argv[3:]
content = source.read_text(encoding="utf-8")
if needle not in content:
    raise SystemExit(f"mutation fixture missing required text: {needle}")
destination.write_text(content.replace(needle, replacement, 1), encoding="utf-8")
PY
  cp "$temporary" "$target"
  set +e
  output="$(check_documentation 2>&1)"
  status=$?
  set -e
  cp "$backup" "$target"
  rm -f "$temporary" "$backup"
  trap - RETURN
  if [[ $status -eq 0 ]]; then
    printf '%s\n' \
      "Codex documentation mutation check failed for '$label'." \
      "The contract could pass after required documentation was removed or forbidden README detail was added." \
      "Make check_documentation reject this mutation, then rerun the test." \
      "documentation checker said: ${output:-exited successfully without diagnostic output}" >&2
    exit 1
  fi
}

check_documentation
assert_mutation_rejected \
  "required NOTES content" "$NOTES" \
  '`seccomp=unconfined`'
assert_mutation_rejected \
  "README security-detail rejection" "$README" \
  "The image includes Codex" \
  "The image includes Codex with seccomp=unconfined"
assert_mutation_rejected \
  "nested bind-source translation" "$CONSUMER_TEST" \
  "translate_bind_source() {"
assert_mutation_rejected \
  "direct-host Docker fallback" "$CONSUMER_TEST" \
  $'else\n  WORKSPACE="$(mktemp -d)"\n  DOCKER_PATH="docker"\nfi'
assert_mutation_rejected \
  "early fixture volume cleanup" "$CONSUMER_TEST" \
  "discover_fixture_volumes() {"
assert_mutation_rejected \
  "UID rewrite bypass" "$CONSUMER_TEST" \
  "run_devcontainer up --update-remote-user-uid-default never"
assert_mutation_rejected \
  "Docker wrapper preflight" "$CONSUMER_TEST" \
  "preflight_docker() {"
