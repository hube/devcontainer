#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
NOTES="$ROOT/.devcontainer/local-features/codex/NOTES.md"
README="$ROOT/README.md"
MANIFEST="$ROOT/.devcontainer/local-features/codex/devcontainer-feature.json"
CONSUMER_TEST="$ROOT/.devcontainer/local-features/codex/test/test-image-consumer.sh"
DESIGN="$ROOT/docs/designs/2026-07-14-codex-unconfined-runtime-design.md"
PLAN="$ROOT/docs/implementation-plans/2026-07-15-codex-unconfined-runtime-implementation-plan.md"
MAINTAINERS="$ROOT/.devcontainer/local-features/codex/MAINTAINERS.md"

check_documentation() {
  python3 - "$NOTES" "$README" "$MANIFEST" "$CONSUMER_TEST" "$DESIGN" "$PLAN" "$MAINTAINERS" <<'PY'
import json
import re
import sys
from pathlib import Path

(
    notes_path,
    readme_path,
    manifest_path,
    consumer_path,
    design_path,
    plan_path,
    maintainers_path,
) = map(Path, sys.argv[1:])
notes = notes_path.read_text(encoding="utf-8")
normalized_notes = " ".join(notes.split())
readme = readme_path.read_text(encoding="utf-8")
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
consumer = consumer_path.read_text(encoding="utf-8")
design = design_path.read_text(encoding="utf-8")
plan = plan_path.read_text(encoding="utf-8")
normalized_plan = " ".join(plan.split())
maintainers = (
    maintainers_path.read_text(encoding="utf-8")
    if maintainers_path.is_file()
    else ""
)
normalized_maintainers = " ".join(maintainers.split())

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
    "empty capability contract": "published `capAdd` is exactly `[]`, so no Docker capabilities are added",
}
failures = [
    f"NOTES missing {label}: {text}"
    for label, text in required_notes.items()
    if text not in normalized_notes
]
for capability in manifest.get("capAdd", []):
    if f"`{capability}`" not in normalized_notes:
        failures.append(f"NOTES missing final capability: {capability}")
if "controlled Docker Desktop capability-subtraction test produced" in normalized_notes:
    failures.append("NOTES defends the settled capAdd contract with an empirical claim")
for forbidden in (
    "## Docker Desktop acceptance",
    "CODEX_RUNTIME_TEST_IMAGE=",
    "test-image-consumer.sh codex-runtime-test:",
    "test-image-consumer.sh ghcr.io/hube/devcontainer:latest",
):
    if forbidden in notes:
        failures.append(f"NOTES contains maintainer-only acceptance procedure: {forbidden}")

notes_link = ".devcontainer/local-features/codex/NOTES.md"
if notes_link not in readme:
    failures.append(f"README missing Codex NOTES link: {notes_link}")
if "Codex" not in readme:
    failures.append("README missing high-level Codex summary")
codex_list_item = re.compile(
    r"(?m)^\* [^\n]*Codex[^\n]*(?:\n  [^\n]*)*"
    r"\.devcontainer/local-features/codex/NOTES\.md"
)
image_contents = re.search(
    r"The devcontainer in this repo includes:\n"
    r"(?P<items>(?:\* [^\n]+\n(?:  [^\n]+\n)*)+)"
    r"\nCode is mounted",
    readme,
)
if image_contents is None:
    failures.append("README image contents list is missing or malformed")
elif not codex_list_item.search(image_contents.group("items")):
    failures.append("README Codex summary/link is not an item in the image contents list")

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

design_statuses = re.findall(r"(?m)^\*\*Status:\*\* .+$", design)
if design_statuses != ["**Status:** Approved."]:
    failures.append(
        "design status is not design-only: "
        + (", ".join(design_statuses) if design_statuses else "missing")
    )

audience_decision = (
    "Decided (owner, 2026-07-16: "
    "https://github.com/hube/devcontainer/pull/47#discussion_r3598141874)"
)
if audience_decision not in design:
    failures.append("design missing the owner-decided NOTES audience boundary")
if "`NOTES.md` is the user reference" not in design:
    failures.append("design does not identify NOTES as the user reference")
maintainers_link = ".devcontainer/local-features/codex/MAINTAINERS.md"
if f"`{maintainers_link}` is the operational authority" not in design:
    failures.append("design does not identify Codex MAINTAINERS as the operational authority")
maintainer_section = re.search(
    r"(?ms)^## Maintainer documentation\n\n(?P<body>.*?)(?=^#|\Z)", readme
)
if maintainer_section is None or maintainers_link not in maintainer_section.group("body"):
    failures.append("README does not link to Codex maintainer documentation")

required_maintainers = {
    "supported runtime": "Docker Desktop in Linux-container mode",
    "stable local image": "codex-runtime-test:acceptance",
    "runtime matrix": "bash .devcontainer/local-features/codex/test/test-runtime.sh",
    "local unrelated consumer": "test-image-consumer.sh codex-runtime-test:acceptance",
    "install-order acceptance": "bash .devcontainer/local-features/agent-skills/test/test-install-order.sh",
    "publication workflow": ".github/workflows/publish.yaml",
    "publication monitoring": "gh run list --workflow publish.yaml --branch main --limit 1",
    "published image pull": "docker pull ghcr.io/hube/devcontainer:latest",
    "post-publication consumer": "test-image-consumer.sh ghcr.io/hube/devcontainer:latest",
    "issue closure gate": "Close issue #36 only after",
    "local image cleanup": "docker image rm -f codex-runtime-test:acceptance",
}
if not maintainers_path.is_file():
    failures.append(f"Codex maintainer documentation is missing: {maintainers_path}")
for label, text in required_maintainers.items():
    if text not in normalized_maintainers:
        failures.append(f"MAINTAINERS missing {label}: {text}")

required_plan = {
    "README list item": "README image contents list",
    "NOTES user boundary": "NOTES is the user reference",
    "maintainer acceptance ownership": "acceptance procedures remain in this plan and the test scripts",
}
for label, text in required_plan.items():
    if text not in normalized_plan:
        failures.append(f"implementation plan missing {label}: {text}")

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
    "fixture container tracking": 'CONTAINERS=()',
    "exact-label container discovery": 'discover_fixture_containers() {',
    "exact-label Docker filter": 'docker ps -aq --filter "label=$FIXTURE_LABEL"',
    "post-up container discovery": 'discover_fixture_containers || exit $?\ndiscover_fixture_volumes || exit $?',
    "cleanup container rediscovery": 'if [[ "$fixture_started" == true ]] && ! discover_fixture_containers; then',
    "all matched-container cleanup": 'for container in "${CONTAINERS[@]}"; do',
}
for label, text in required_consumer.items():
    if text not in consumer:
        failures.append(f"consumer test missing {label}: {text}")

for forbidden in ('"features"', '"runArgs"', '"mounts"', '"securityOpt"', '"capAdd"'):
    if forbidden in consumer:
        failures.append(f"consumer test adds forbidden config material: {forbidden}")
if 'if [[ -n "$CONTAINER_ID" ]]; then' in consumer:
    failures.append("consumer cleanup still depends on the parsed containerId")

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

assert_moved_readme_bullet_rejected() {
  local temporary backup output status
  temporary="$(mktemp)"
  backup="$(mktemp)"
  cp "$README" "$backup"
  trap 'cp "$backup" "$README"; rm -f "$temporary" "$backup"' RETURN
  python3 - "$README" "$temporary" <<'PY'
import sys
from pathlib import Path

source, destination = map(Path, sys.argv[1:])
content = source.read_text(encoding="utf-8")
bullet = (
    "* Codex; its supported runtime and operator guidance are in the\n"
    "  [Codex feature notes](.devcontainer/local-features/codex/NOTES.md).\n"
)
if bullet not in content:
    raise SystemExit("mutation fixture missing intact README Codex bullet")
without_bullet = content.replace(bullet, "", 1)
destination.write_text(without_bullet.rstrip() + "\n\n" + bullet, encoding="utf-8")
PY
  cp "$temporary" "$README"
  set +e
  output="$(check_documentation 2>&1)"
  status=$?
  set -e
  cp "$backup" "$README"
  rm -f "$temporary" "$backup"
  trap - RETURN
  if [[ $status -eq 0 ]]; then
    printf '%s\n' \
      "Codex documentation mutation check failed for 'README Codex contents-list boundary'." \
      "The contract accepted the intact Codex bullet after it was moved outside the introductory image-contents list." \
      "Constrain the Codex bullet check to that list, then rerun the test." \
      "documentation checker said: ${output:-exited successfully without diagnostic output}" >&2
    exit 1
  fi
}

check_documentation
assert_mutation_rejected \
  "required NOTES content" "$NOTES" \
  '`seccomp=unconfined`'
assert_mutation_rejected \
  "maintainer acceptance rejection" "$NOTES" \
  "[1]: https://github.com/devcontainers/features/tree/main/src/sshd" \
  $'test-image-consumer.sh ghcr.io/hube/devcontainer:latest\n\n[1]: https://github.com/devcontainers/features/tree/main/src/sshd'
assert_mutation_rejected \
  "settled empty capability contract" "$NOTES" \
  'published `capAdd` is exactly `[]`'
assert_mutation_rejected \
  "README security-detail rejection" "$README" \
  "* Codex;" \
  "* Codex with seccomp=unconfined;"
assert_mutation_rejected \
  "README Codex list placement" "$README" \
  "* Codex;" \
  "Codex;"
assert_moved_readme_bullet_rejected
assert_mutation_rejected \
  "design-only status" "$DESIGN" \
  "**Status:** Approved." \
  "**Status:** Approved; implementation complete."
assert_mutation_rejected \
  "design NOTES audience boundary" "$DESIGN" \
  '`NOTES.md` is the user reference'
assert_mutation_rejected \
  "design maintainer operational authority" "$DESIGN" \
  ".devcontainer/local-features/codex/MAINTAINERS.md"
assert_mutation_rejected \
  "README maintainer documentation link" "$README" \
  ".devcontainer/local-features/codex/MAINTAINERS.md"
assert_mutation_rejected \
  "maintainer local acceptance" "$MAINTAINERS" \
  "bash .devcontainer/local-features/codex/test/test-runtime.sh"
assert_mutation_rejected \
  "maintainer publication workflow" "$MAINTAINERS" \
  "gh run list --workflow publish.yaml --branch main --limit 1"
assert_mutation_rejected \
  "maintainer post-publication acceptance" "$MAINTAINERS" \
  "test-image-consumer.sh ghcr.io/hube/devcontainer:latest"
assert_mutation_rejected \
  "maintainer issue closure gate" "$MAINTAINERS" \
  "Close issue #36 only after"
assert_mutation_rejected \
  "plan NOTES audience boundary" "$PLAN" \
  "NOTES is the user reference"
assert_mutation_rejected \
  "plan maintainer acceptance ownership" "$PLAN" \
  "acceptance procedures remain in"
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
assert_mutation_rejected \
  "exact-label container discovery" "$CONSUMER_TEST" \
  "discover_fixture_containers() {"
assert_mutation_rejected \
  "post-up container discovery" "$CONSUMER_TEST" \
  $'discover_fixture_containers || exit $?\ndiscover_fixture_volumes || exit $?'
assert_mutation_rejected \
  "cleanup container rediscovery" "$CONSUMER_TEST" \
  'if [[ "$fixture_started" == true ]] && ! discover_fixture_containers; then'
