#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || -z "${1:-}" ]]; then
  printf '%s\n' \
    "Codex image-consumer input validation failed because exactly one non-empty image argument is required, but $# arguments were supplied." \
    "The test cannot create an unrelated consumer for a known image." \
    "Run '$0 IMAGE' with one stable local or published image reference." \
    "argument parser said: received arguments: ${*:-<none>}" >&2
  exit 2
fi

IMAGE="$1"
LOCAL_HOME="$HOME"
NPM_CACHE="${npm_config_cache:-${NPM_CONFIG_CACHE:-$HOME/.npm}}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
HARNESS_ROOT="$(mktemp -d)"
MAPPINGS="$HARNESS_ROOT/mount-mappings"
DOCKER_PATH="docker"
CLI_HOME="$HOME"
WORKSPACE=""
CONTAINER_ID=""
VOLUMES=()
fixture_started=false

diagnostic() {
  local problem="$1"
  local consequence="$2"
  local remedy="$3"
  local command_name="$4"
  local output="$5"
  local status="$6"
  printf '%s %s %s %s said: %s\n' \
    "$problem" "$consequence" "$remedy" "$command_name" \
    "${output:-exited with status $status without diagnostic output}" >&2
}

if [[ -e /.dockerenv ]]; then
  inspect_output="$(docker inspect "$(hostname)" 2>&1)" || {
    status=$?
    diagnostic \
      "Codex image-consumer outer-container inspection failed." \
      "The nested harness cannot translate its workspace and HOME bind sources for the Docker Desktop daemon." \
      "Run the test from a Docker-visible outer bind mount or directly from the Docker Desktop host." \
      "docker inspect" "$inspect_output" "$status"
    exit "$status"
  }
  mount_context="$(python3 - "$REPO_ROOT" "$LOCAL_HOME" "$inspect_output" <<'PY'
import json
import os
import sys

repo_root, local_home, raw = sys.argv[1:]
inspection = json.loads(raw)
if len(inspection) != 1:
    raise SystemExit(f"expected one current-container inspection, got {len(inspection)}")
mounts = [
    (mount.get("Destination", ""), mount.get("Source", ""))
    for mount in inspection[0].get("Mounts", [])
    if mount.get("Type") == "bind"
]
mounts.sort(key=lambda item: len(item[0]), reverse=True)

workspace_candidates = [
    item for item in mounts
    if repo_root == item[0] or repo_root.startswith(item[0].rstrip("/") + "/")
]
if not workspace_candidates:
    raise SystemExit(f"no outer bind destination contains repository {repo_root}")
outer_workspace_destination = workspace_candidates[0][0]

home_candidates = []
for destination, source in mounts:
    if not destination.startswith(local_home.rstrip("/") + "/"):
        continue
    suffix = destination[len(local_home):]
    if suffix and source.endswith(suffix):
        home_candidates.append(source[:-len(suffix)])
if not home_candidates:
    raise SystemExit(f"no outer bind mapping resolves host HOME from {local_home}")
host_home = home_candidates[0]

print(outer_workspace_destination)
print(host_home)
for destination, source in mounts:
    if destination and source:
        print(f"{destination}\t{source}")
PY
    2>&1)" || {
    status=$?
    diagnostic \
      "Codex image-consumer outer mount mapping failed." \
      "The nested harness cannot create daemon-visible bind sources without a verified destination-to-source map." \
      "Expose the repository and host-home files through outer bind mounts, then rerun the test." \
      "mount mapping resolver" "$mount_context" "$status"
    exit "$status"
  }
  mapfile -t context_lines <<<"$mount_context"
  if [[ ${#context_lines[@]} -lt 3 ]]; then
    diagnostic \
      "Codex image-consumer outer mount mapping returned incomplete context." \
      "The nested harness cannot safely translate Docker bind sources." \
      "Restore the repository and host-home bind mappings, then rerun the test." \
      "mount mapping resolver" "$mount_context" 1
    exit 1
  fi
  OUTER_WORKSPACE_DESTINATION="${context_lines[0]}"
  CLI_HOME="${context_lines[1]}"
  printf '%s\n' "${context_lines[@]:2}" >"$MAPPINGS"
  WORKSPACE="$(mktemp -d "$OUTER_WORKSPACE_DESTINATION/.codex-image-consumer.XXXXXX")"
  DOCKER_PATH="$HARNESS_ROOT/docker"
  cat >"$DOCKER_PATH" <<'WRAPPER'
#!/usr/bin/env bash
set -euo pipefail

translate_bind_source() {
  local path="$1"
  local destination source
  while IFS=$'\t' read -r destination source; do
    if [[ "$path" == "$destination" || "$path" == "$destination/"* ]]; then
      printf '%s%s' "$source" "${path#"$destination"}"
      return
    fi
  done <"$CODEX_CONSUMER_MAPPINGS"
  printf '%s' "$path"
}

translate_mount() {
  local specification="$1"
  local fields field index
  IFS=, read -ra fields <<<"$specification"
  if [[ ",${specification}," != *,type=bind,* ]]; then
    printf '%s' "$specification"
    return
  fi
  for index in "${!fields[@]}"; do
    field="${fields[$index]}"
    case "$field" in
      source=*|src=*)
        fields[$index]="${field%%=*}=$(translate_bind_source "${field#*=}")"
        ;;
    esac
  done
  (IFS=,; printf '%s' "${fields[*]}")
}

translate_volume() {
  local specification="$1"
  local source="${specification%%:*}"
  if [[ "$source" == /* ]]; then
    printf '%s%s' "$(translate_bind_source "$source")" "${specification#"$source"}"
  else
    printf '%s' "$specification"
  fi
}

args=("$@")
for ((index = 0; index < ${#args[@]}; index++)); do
  case "${args[$index]}" in
    --mount)
      ((index + 1 < ${#args[@]})) && args[$((index + 1))]="$(translate_mount "${args[$((index + 1))]}")"
      ;;
    --mount=*)
      args[$index]="--mount=$(translate_mount "${args[$index]#--mount=}")"
      ;;
    --volume|-v)
      ((index + 1 < ${#args[@]})) && args[$((index + 1))]="$(translate_volume "${args[$((index + 1))]}")"
      ;;
    --volume=*|-v=*)
      option="${args[$index]%%=*}"
      args[$index]="$option=$(translate_volume "${args[$index]#*=}")"
      ;;
  esac
done
exec "$CODEX_CONSUMER_REAL_DOCKER" "${args[@]}"
WRAPPER
  chmod 755 "$DOCKER_PATH"
else
  WORKSPACE="$(mktemp -d)"
  DOCKER_PATH="docker"
fi

CONFIG_DIR="$WORKSPACE/.devcontainer"
CONFIG="$CONFIG_DIR/devcontainer.json"
FIXTURE_TOKEN="$(date +%s)-$$-$RANDOM"
FIXTURE_LABEL="codex.image-consumer=$FIXTURE_TOKEN"
DEVCONTAINER_ID="$(python3 - "$FIXTURE_TOKEN" <<'PY'
import hashlib
import json
import sys

canonical = json.dumps(
    {"codex.image-consumer": sys.argv[1]},
    separators=(",", ":"),
    sort_keys=True,
)
number = int.from_bytes(hashlib.sha256(canonical.encode()).digest(), "big")
alphabet = "0123456789abcdefghijklmnopqrstuv"
encoded = ""
while number:
    number, remainder = divmod(number, 32)
    encoded = alphabet[remainder] + encoded
print(encoded.rjust(52, "0"))
PY
)"
CLI_COMMON_ARGS=(
  --docker-path "$DOCKER_PATH"
  --workspace-folder "$WORKSPACE"
  --config "$CONFIG"
  --id-label "$FIXTURE_LABEL"
)

discover_fixture_volumes() {
  local output status volume known
  output="$(docker volume ls --format '{{.Name}}' 2>&1)" || {
    status=$?
    diagnostic \
      "Codex image-consumer fixture-volume discovery failed for suffix '$DEVCONTAINER_ID'." \
      "The harness cannot guarantee cleanup of fixture-owned volumes created before a container ID was reported." \
      "Resolve Docker access, remove volumes ending in '-$DEVCONTAINER_ID', and rerun the test." \
      "docker volume ls" "$output" "$status"
    return "$status"
  }
  while IFS= read -r volume; do
    [[ "$volume" == *-"$DEVCONTAINER_ID" ]] || continue
    known=false
    for existing in "${VOLUMES[@]}"; do
      [[ "$existing" == "$volume" ]] && known=true
    done
    [[ "$known" == false ]] && VOLUMES+=("$volume")
  done <<<"$output"
}

cleanup() {
  local original_status=$?
  local cleanup_failed=false output status volume
  trap - EXIT

  if [[ "$fixture_started" == true ]] && ! discover_fixture_volumes; then
    cleanup_failed=true
  fi

  if [[ -n "$CONTAINER_ID" ]]; then
    set +e
    output="$(docker rm -f -v "$CONTAINER_ID" 2>&1)"
    status=$?
    set -e
    if [[ $status -ne 0 ]]; then
      diagnostic \
        "Codex image-consumer cleanup failed because container '$CONTAINER_ID' could not be removed." \
        "The temporary consumer container remains on the Docker engine." \
        "Resolve Docker access and remove it with 'docker rm -f -v $CONTAINER_ID'." \
        "docker rm" "$output" "$status"
      cleanup_failed=true
    fi
  fi

  for volume in "${VOLUMES[@]}"; do
    set +e
    output="$(docker volume rm -f "$volume" 2>&1)"
    status=$?
    set -e
    if [[ $status -ne 0 ]]; then
      diagnostic \
        "Codex image-consumer cleanup failed because fixture-owned volume '$volume' could not be removed." \
        "Consumer state remains on the Docker engine." \
        "Resolve Docker access and remove it with 'docker volume rm -f $volume'." \
        "docker volume rm" "$output" "$status"
      cleanup_failed=true
    fi
  done

  rm -rf "$WORKSPACE" "$HARNESS_ROOT"
  if [[ "$cleanup_failed" == true ]]; then
    exit 1
  fi
  exit "$original_status"
}
trap cleanup EXIT

run_devcontainer() {
  local command="$1"
  shift
  HOME="$CLI_HOME" npm_config_cache="$NPM_CACHE" \
    CODEX_CONSUMER_REAL_DOCKER="$(command -v docker)" \
    CODEX_CONSUMER_MAPPINGS="$MAPPINGS" \
    npx -y @devcontainers/cli@latest "$command" "${CLI_COMMON_ARGS[@]}" "$@"
}

preflight_docker() {
  CODEX_CONSUMER_REAL_DOCKER="$(command -v docker)" \
    CODEX_CONSUMER_MAPPINGS="$MAPPINGS" \
    "$DOCKER_PATH" info --format '{{.OperatingSystem}}'
}

mkdir -p "$CONFIG_DIR"
printf '%s\n' \
  '{' \
  "  \"image\": \"$IMAGE\"," \
  '  "appPort": ["127.0.0.1::2222"]' \
  '}' >"$CONFIG"

config_output="$(python3 - "$CONFIG" "$IMAGE" <<'PY'
import json
import sys

path, image = sys.argv[1:]
with open(path, encoding="utf-8") as stream:
    config = json.load(stream)
expected = {"image": image, "appPort": ["127.0.0.1::2222"]}
if config != expected or list(config) != ["image", "appPort"]:
    raise SystemExit(f"expected only image and appPort, got {config!r}")
PY
  2>&1)" || {
  status=$?
  diagnostic \
    "Codex image-consumer configuration generation failed." \
    "The test would no longer represent an unrelated two-key image consumer." \
    "Restore the generated configuration to only image and appPort, then rerun the test." \
    "configuration checker" "$config_output" "$status"
  exit "$status"
}

preflight_output="$(preflight_docker 2>&1)" || {
  status=$?
  diagnostic \
    "Codex image-consumer Docker wrapper preflight failed." \
    "The Dev Container CLI could hide wrapper translation errors behind its own stack trace." \
    "Correct the reported wrapper or Docker access failure, then rerun the test." \
    "Docker wrapper" "$preflight_output" "$status"
  exit "$status"
}
if [[ "$preflight_output" != "Docker Desktop" ]]; then
  diagnostic \
    "Codex image-consumer found '$preflight_output' instead of Docker Desktop through its Docker wrapper." \
    "The unrelated-consumer result would not cover the sole supported runtime." \
    "Run the test against Docker Desktop in Linux-container mode." \
    "Docker wrapper" "$preflight_output" 1
  exit 1
fi

fixture_started=true
set +e
up_output="$(run_devcontainer up --update-remote-user-uid-default never 2>&1)"
up_status=$?
set -e
CONTAINER_ID="$(python3 - "$up_output" <<'PY'
import json
import sys

for line in reversed(sys.argv[1].splitlines()):
    try:
        value = json.loads(line)
    except json.JSONDecodeError:
        continue
    if isinstance(value, dict) and value.get("containerId"):
        print(value["containerId"])
        break
PY
)"
discover_fixture_volumes || exit $?
if [[ $up_status -ne 0 ]]; then
  diagnostic \
    "Codex image-consumer container creation failed for image '$IMAGE'." \
    "The image's embedded post-create health contract did not produce a usable unrelated consumer." \
    "Correct the reported Docker Desktop, image metadata, or health-check failure and rerun the test." \
    "devcontainer up" "$up_output" "$up_status"
  exit "$up_status"
fi
if [[ -z "$CONTAINER_ID" ]]; then
  diagnostic \
    "Codex image-consumer could not identify the created container." \
    "The test cannot execute checks or guarantee cleanup of the consumer." \
    "Use a Dev Container CLI that reports containerId in its successful output." \
    "devcontainer up output parser" "$up_output" 1
  exit 1
fi

set +e
consumer_output="$(run_devcontainer exec \
  bash -lc 'set -euo pipefail
git init --quiet
printf "%s\n" before > tracked.txt
git add tracked.txt
patch_output="$(codex sandbox -P :workspace -C "$PWD" apply_patch <<'"'"'PATCH'"'"' 2>&1
*** Begin Patch
*** Update File: tracked.txt
@@
-before
+after
*** End Patch
PATCH
)" || {
  status=$?
  printf "%s\n" "Codex sandboxed apply_patch failed. The unrelated consumer cannot persist a sandboxed workspace edit. Restore the Codex sandbox and apply_patch integration, then recreate the container. codex sandbox said: ${patch_output:-exited with status $status without diagnostic output}" >&2
  exit "$status"
}
if git diff --exit-code > /tmp/codex-consumer-diff-output 2>&1; then
  output="$(cat /tmp/codex-consumer-diff-output)"
  printf "%s\n" "Codex sandboxed apply_patch did not leave a tracked-file change. Patch persistence was not verified. Ensure apply_patch modifies tracked.txt inside the workspace and rerun the test. git diff said: ${output:-exited successfully without showing a change}" >&2
  exit 1
fi
diff_output="$(cat /tmp/codex-consumer-diff-output)"
check_output="$(git diff --check 2>&1)" || {
  status=$?
  printf "%s\n" "Codex sandboxed apply_patch produced an invalid diff. The persisted consumer change contains whitespace errors. Correct the patch and rerun the test. git diff --check said: ${check_output:-exited with status $status without diagnostic output}" >&2
  exit "$status"
}
printf "%s\n" "$patch_output" "$diff_output"' 2>&1)"
consumer_status=$?
set -e
if [[ $consumer_status -ne 0 ]]; then
  diagnostic \
    "Codex image-consumer sandboxed patch verification failed for image '$IMAGE'." \
    "The unrelated consumer did not prove that a tracked-file edit persists through Codex's sandbox." \
    "Correct the reported Git, Codex sandbox, or apply_patch failure and rerun the test." \
    "devcontainer exec" "$consumer_output" "$consumer_status"
  exit "$consumer_status"
fi

printf "Image '%s': post-create health and sandboxed patch persistence were verified.\n" "$IMAGE"
