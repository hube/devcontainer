#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
CANDIDATES=(SYS_ADMIN SYS_CHROOT SETUID SETGID SYS_PTRACE)
SECURITY_OPTIONS=(seccomp=unconfined apparmor=unconfined)
BUILD_LOG="$(mktemp)"
WRAPPER_VOLUME="codex-runtime-wrapper-$(date +%s)-$$"
WRAPPER_MOUNT="type=volume,src=$WRAPPER_VOLUME,dst=/codex-runtime-test"
generated_image=false
volume_created=false

if [[ -n "${CODEX_RUNTIME_TEST_IMAGE:-}" ]]; then
  IMAGE="$CODEX_RUNTIME_TEST_IMAGE"
else
  IMAGE="codex-runtime-test:$(date +%s)-$$"
  generated_image=true
fi

cleanup() {
  local original_status=$?
  local cleanup_failed=false cleanup_output cleanup_status cleanup_detail
  trap - EXIT

  set +e
  cleanup_output="$(rm -f "$BUILD_LOG" 2>&1)"
  cleanup_status=$?
  set -e
  if [[ $cleanup_status -ne 0 ]]; then
    cleanup_detail="${cleanup_output//$'\r'/\\r}"
    cleanup_detail="${cleanup_detail//$'\n'/\\n}"
    printf '%s\n' \
      "Codex runtime test cleanup failed because build log '$BUILD_LOG' could not be removed. Temporary test output remains on the filesystem. Remove it after restoring filesystem access. rm said: ${cleanup_detail:-rm exited with status $cleanup_status without diagnostic output}" >&2
    cleanup_failed=true
  fi
  if [[ "$volume_created" == true ]]; then
    set +e
    cleanup_output="$(docker volume rm -f "$WRAPPER_VOLUME" 2>&1)"
    cleanup_status=$?
    set -e
    if [[ $cleanup_status -ne 0 ]]; then
      cleanup_detail="${cleanup_output//$'\r'/\\r}"
      cleanup_detail="${cleanup_detail//$'\n'/\\n}"
      printf '%s\n' \
        "Codex runtime test cleanup failed because wrapper volume '$WRAPPER_VOLUME' could not be removed. The test volume remains on the Docker engine. Remove it with 'docker volume rm -f $WRAPPER_VOLUME' after resolving Docker access. docker volume rm said: ${cleanup_detail:-docker volume rm exited with status $cleanup_status without diagnostic output}" >&2
      cleanup_failed=true
    fi
  fi
  if [[ "$generated_image" == true ]]; then
    set +e
    cleanup_output="$(docker image rm -f "$IMAGE" 2>&1)"
    cleanup_status=$?
    set -e
    if [[ $cleanup_status -ne 0 ]]; then
      cleanup_detail="${cleanup_output//$'\r'/\\r}"
      cleanup_detail="${cleanup_detail//$'\n'/\\n}"
      printf '%s\n' \
        "Codex runtime test cleanup failed because the temporary image '$IMAGE' could not be removed. The temporary image remains on the Docker engine. Remove it with 'docker image rm -f $IMAGE' after resolving Docker access. docker image rm said: ${cleanup_detail:-docker image rm exited with status $cleanup_status without diagnostic output}" >&2
      cleanup_failed=true
    fi
  fi
  if [[ "$cleanup_failed" == true ]]; then
    exit 1
  fi
  exit "$original_status"
}
trap cleanup EXIT

if [[ "${CODEX_RUNTIME_CLEANUP_TEST:-}" == 1 ]]; then
  BUILD_LOG="${CODEX_RUNTIME_CLEANUP_TEST_BUILD_LOG:?cleanup test build log is required}"
  WRAPPER_VOLUME="${CODEX_RUNTIME_CLEANUP_TEST_VOLUME:?cleanup test volume is required}"
  IMAGE="${CODEX_RUNTIME_CLEANUP_TEST_IMAGE:?cleanup test image is required}"
  volume_created=true
  generated_image=true
  exit "${CODEX_RUNTIME_CLEANUP_TEST_STATUS:?cleanup test status is required}"
fi

fail_with_output() {
  local problem="$1"
  local consequence="$2"
  local remedy="$3"
  local source="$4"
  local output="$5"
  local status="${6:-1}"
  printf '%s\n' "$problem $consequence $remedy $source said:" >&2
  printf '%s\n' "${output:-$source exited with status $status without diagnostic output}" >&2
  exit 1
}

DOCKER_OPERATING_SYSTEM="$(docker info --format '{{.OperatingSystem}}' 2>&1)" || {
  status=$?
  fail_with_output \
    "Codex runtime Docker daemon identity inspection failed." \
    "Capability derivation cannot verify that it targets the supported Docker Desktop runtime." \
    "Connect a working Docker Desktop Linux engine and rerun this test." \
    "docker info OperatingSystem" "$DOCKER_OPERATING_SYSTEM" "$status"
}
if [[ "$DOCKER_OPERATING_SYSTEM" != "Docker Desktop" ]]; then
  fail_with_output \
    "Codex runtime Docker daemon identity was '$DOCKER_OPERATING_SYSTEM', expected 'Docker Desktop'." \
    "A native-Linux or other engine cannot publish the supported-runtime capability derivation result." \
    "Connect Docker Desktop in Linux-container mode and rerun this test." \
    "docker info OperatingSystem" "$DOCKER_OPERATING_SYSTEM" 1
fi

if npx -y @devcontainers/cli@latest build \
  --workspace-folder "$REPO_ROOT" --image-name "$IMAGE" >"$BUILD_LOG" 2>&1; then
  :
else
  status=$?
  fail_with_output \
    "Codex runtime image build failed." \
    "The image boundary and runtime capability contract cannot be tested." \
    "Resolve the Dev Container build failure and rerun this test." \
    "devcontainer build" "$(<"$BUILD_LOG")" "$status"
fi

metadata_output="$(docker inspect "$IMAGE" --format '{{ index .Config.Labels "devcontainer.metadata" }}' 2>&1)" || {
  status=$?
  fail_with_output \
    "Codex runtime metadata inspection failed." \
    "The embedded Feature contract cannot be verified at the image boundary." \
    "Ensure the built image exists and Docker can inspect it, then rerun this test." \
    "docker inspect" "$metadata_output" "$status"
}

metadata_check_output="$(printf '%s' "$metadata_output" | python3 -c '
import json
import pathlib
import sys

repo_root = pathlib.Path(sys.argv[1])
manifest = json.loads(
    (repo_root / ".devcontainer/local-features/codex/devcontainer-feature.json").read_text()
)
metadata = json.load(sys.stdin)
entries = [entry for entry in metadata if entry.get("id") == "./local-features/codex"]

def check(condition, message):
    if not condition:
        raise SystemExit(message)

check(len(entries) == 1, f"expected one Codex metadata entry, got {len(entries)}")
entry = entries[0]
expected_security = ["seccomp=unconfined", "apparmor=unconfined"]
check(entry.get("securityOpt") == expected_security,
      f"securityOpt mismatch: {entry.get('"'"'securityOpt'"'"')!r}")
check(entry.get("capAdd") == manifest.get("capAdd"),
      f"capAdd mismatch: image={entry.get('"'"'capAdd'"'"')!r}, manifest={manifest.get('"'"'capAdd'"'"')!r}")
check(entry.get("postCreateCommand") == "~/bin/devcontainer-feature/codex/postCreateScript.sh",
      f"postCreateCommand mismatch: {entry.get('"'"'postCreateCommand'"'"')!r}")
for option in entry.get("securityOpt", []):
    if option.startswith("seccomp="):
        value = option.partition("=")[2]
        check(value == "unconfined" and "/" not in value and "${" not in value,
              f"filesystem-backed seccomp value is forbidden: {option}")
' "$REPO_ROOT" 2>&1)" || {
  status=$?
  fail_with_output \
    "Codex runtime metadata contract check failed." \
    "Consumers cannot be shown to inherit a self-contained Codex runtime contract from the image." \
    "Correct the Codex Feature metadata and rebuild the image." \
    "metadata checker" "$metadata_check_output" "$status"
}

IMAGE_USER="$(python3 - "$REPO_ROOT/.devcontainer/devcontainer.json" <<'PY'
import json
import os
import pathlib
import re
import sys

config = json.loads(
    re.sub(r"(?m)^\s*//.*$", "", pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
)
configured_user = config.get("containerUser")
if not isinstance(configured_user, str) or not configured_user:
    raise SystemExit(f"containerUser must be a non-empty string, got {configured_user!r}")

substitution = re.fullmatch(r"\$\{localEnv:([A-Za-z_][A-Za-z0-9_]*):([^}]*)\}", configured_user)
if substitution:
    environment_name, default = substitution.groups()
    resolved_user = os.environ.get(environment_name, default)
elif "${" in configured_user:
    raise SystemExit(f"unsupported containerUser substitution: {configured_user}")
else:
    resolved_user = configured_user

if not re.fullmatch(r"[a-z_][a-z0-9_-]*\$?", resolved_user or ""):
    raise SystemExit(f"containerUser must resolve to a named Linux user, got {resolved_user!r}")
if resolved_user == "root":
    raise SystemExit("containerUser resolved to root")
print(resolved_user)
PY
  2>&1)" || {
  status=$?
  fail_with_output \
    "Codex runtime containerUser resolution failed." \
    "The built image cannot be tested as the user declared by the Dev Container configuration." \
    "Set containerUser to a named non-root user or a supported localEnv substitution, then rerun this test." \
    "containerUser resolver" "$IMAGE_USER" "$status"
}

identity_output="$(docker run --rm --user "$IMAGE_USER" "$IMAGE" sh -c '
  passwd_entry="$(getent passwd "$1")" || exit $?
  passwd_home="${passwd_entry#*:*:*:*:*:}"
  passwd_home="${passwd_home%%:*}"
  printf "%s\n%s\n%s\n%s\n" "$(id -un)" "$(id -u)" "$passwd_home" "$PATH"
' sh "$IMAGE_USER" 2>&1)" || {
  status=$?
  fail_with_output \
    "Codex runtime identity discovery failed for image user '$IMAGE_USER'." \
    "The controlled probes cannot hold HOME and PATH constant." \
    "Ensure the image container user can start a shell, then rerun this test." \
    "docker run" "$identity_output" "$status"
}
mapfile -t identity < <(printf '%s\n' "$identity_output")
if [[ ${#identity[@]} -ne 4 || "${identity[0]}" != "$IMAGE_USER" || \
  "${identity[1]}" == 0 || -z "${identity[2]}" || -z "${identity[3]}" ]]; then
  fail_with_output \
    "Codex runtime identity discovery did not resolve '$IMAGE_USER' to the expected named non-root account with HOME and PATH." \
    "The controlled probes cannot exercise or hold constant the configured container-user environment." \
    "Ensure containerUser names a non-root account present in the image, then rerun this test." \
    "docker run" "$identity_output" 1
fi
IMAGE_HOME="${identity[2]}"
IMAGE_PATH="${identity[3]}"
HOOK="$IMAGE_HOME/bin/devcontainer-feature/codex/postCreateScript.sh"
CODEX_PATH="$IMAGE_HOME/.local/bin/codex"

codex_check_output="$(docker run --rm --user "$IMAGE_USER" "$IMAGE" \
  test -x "$CODEX_PATH" 2>&1)" || {
  status=$?
  fail_with_output \
    "Codex runtime CLI verification failed because '$CODEX_PATH' is not executable as '$IMAGE_USER'." \
    "The health hook cannot launch Codex, so no sandbox comparison is valid." \
    "Restore the Codex installer output at '$CODEX_PATH', rebuild the image, and rerun this test." \
    "docker run test -x" "$codex_check_output" "$status"
}

stat_output="$(docker run --rm --user "$IMAGE_USER" "$IMAGE" \
  stat -c '%U:%G %a %n' /usr/bin/bwrap 2>&1)" || {
  status=$?
  fail_with_output \
    "Codex runtime Bubblewrap inspection failed as image user '$IMAGE_USER'." \
    "The image cannot prove that its container user sees the required system Bubblewrap installation." \
    "Install and configure /usr/bin/bwrap in the Codex Feature, then rebuild the image." \
    "docker run stat" "$stat_output" "$status"
}
if [[ "$stat_output" != "root:root 4755 /usr/bin/bwrap" ]]; then
  fail_with_output \
    "Codex runtime Bubblewrap metadata was '$stat_output', expected 'root:root 4755 /usr/bin/bwrap'." \
    "The image cannot safely use the required setuid system Bubblewrap." \
    "Restore root ownership and mode 4755 in the Codex Feature, then rebuild the image." \
    "docker run stat" "$stat_output" 1
fi

volume_output="$(docker volume create "$WRAPPER_VOLUME" 2>&1)" || {
  status=$?
  fail_with_output \
    "Codex runtime wrapper volume creation failed." \
    "The system Bubblewrap selection cannot be instrumented without a daemon-visible shared volume." \
    "Resolve Docker volume access and rerun this test." \
    "docker volume create" "$volume_output" "$status"
}
volume_created=true
if [[ "$volume_output" != "$WRAPPER_VOLUME" ]]; then
  fail_with_output \
    "Codex runtime wrapper volume creation returned '$volume_output', expected '$WRAPPER_VOLUME'." \
    "The test cannot prove which Docker volume will be shared by every probe." \
    "Remove the unexpected volume and rerun this test with a working Docker engine." \
    "docker volume create" "$volume_output" 1
fi

initialize_wrapper_volume() {
  local output status
  output="$(docker run --rm --user root --mount "$WRAPPER_MOUNT" \
    "$IMAGE" bash -c '
      cat > /codex-runtime-test/bwrap <<'"'"'WRAPPER'"'"'
#!/usr/bin/env bash
printf '"'"'%q '"'"' "$@" >>"$BWRAP_LOG"
printf '"'"'\n'"'"' >>"$BWRAP_LOG"
exec /usr/bin/bwrap "$@"
WRAPPER
      chmod 755 /codex-runtime-test/bwrap
      : > /codex-runtime-test/bwrap.log
      chmod 666 /codex-runtime-test/bwrap.log
    ' 2>&1)" || {
    status=$?
    fail_with_output \
      "Codex runtime wrapper volume initialization failed." \
      "The probes cannot instrument or log system Bubblewrap selection." \
      "Ensure the built image can populate the Docker volume, then rerun this test." \
      "wrapper initialization container" "$output" "$status"
  }
}

reset_wrapper_log() {
  local output status
  output="$(docker run --rm --user "$IMAGE_USER" --mount "$WRAPPER_MOUNT" \
    "$IMAGE" sh -c ': > /codex-runtime-test/bwrap.log' 2>&1)" || {
    status=$?
    fail_with_output \
      "Codex runtime wrapper log reset failed." \
      "The next probe could be confused with Bubblewrap selections from an earlier comparison." \
      "Restore writable wrapper-volume permissions and rerun the complete test." \
      "wrapper reset container" "$output" "$status"
  }
}

read_wrapper_log() {
  local output status
  output="$(docker run --rm --user "$IMAGE_USER" --mount "$WRAPPER_MOUNT" \
    "$IMAGE" cat /codex-runtime-test/bwrap.log 2>&1)" || {
    status=$?
    fail_with_output \
      "Codex runtime wrapper log read failed." \
      "The probe cannot prove whether Codex selected the system Bubblewrap executable." \
      "Restore readable wrapper-volume permissions and rerun the complete test." \
      "wrapper read container" "$output" "$status"
  }
  printf '%s' "$output"
}

initialize_wrapper_volume

PROBE_STATUS=0
PROBE_OUTPUT=""
PROBE_BWRAP_LOG=""
run_probe() {
  local name="$1"
  shift
  reset_wrapper_log
  set +e
  PROBE_OUTPUT="$(timeout 45s docker run --rm \
    --user "$IMAGE_USER" \
    --env "HOME=$IMAGE_HOME" \
    --env "PATH=/codex-runtime-test:$IMAGE_HOME/.local/bin:$IMAGE_PATH" \
    --env "BWRAP_LOG=/codex-runtime-test/bwrap.log" \
    --workdir /tmp \
    --mount "$WRAPPER_MOUNT" \
    "$@" \
    "$IMAGE" "$HOOK" 2>&1)"
  PROBE_STATUS=$?
  set -e
  PROBE_BWRAP_LOG="$(read_wrapper_log)"
  printf 'PROBE=%s\nSTATUS=%s\nOUTPUT_BEGIN\n%s\nOUTPUT_END\nBWRAP_LOG_BEGIN\n%s\nBWRAP_LOG_END\n' \
    "$name" "$PROBE_STATUS" "$PROBE_OUTPUT" "$PROBE_BWRAP_LOG"
}

full_runtime_args=()
for option in "${SECURITY_OPTIONS[@]}"; do
  full_runtime_args+=(--security-opt "$option")
done
for capability in "${CANDIDATES[@]}"; do
  full_runtime_args+=(--cap-add "$capability")
done

control_args=()
for capability in "${CANDIDATES[@]}"; do
  control_args+=(--cap-add "$capability")
done
run_probe control-default-security "${control_args[@]}"
if [[ $PROBE_STATUS -eq 0 ]]; then
  fail_with_output \
    "Codex runtime retirement control unexpectedly passed with Docker's default seccomp and AppArmor settings." \
    "The published unconfined options may no longer be necessary and this test must not preserve obsolete relaxations." \
    "Reevaluate and redesign the outer-runtime contract before updating this test." \
    "control probe" "$PROBE_OUTPUT" "$PROBE_STATUS"
fi
CONTROL_RESTRICTION="bwrap: pivot_root: Operation not permitted"
if [[ -z "$PROBE_BWRAP_LOG" || "$PROBE_OUTPUT" != *"$CONTROL_RESTRICTION"* ]]; then
  control_evidence="$(printf 'OUTPUT_BEGIN\n%s\nOUTPUT_END\nBWRAP_LOG_BEGIN\n%s\nBWRAP_LOG_END' \
    "$PROBE_OUTPUT" "$PROBE_BWRAP_LOG")"
  fail_with_output \
    "Codex runtime default-security control failed without proving the expected '$CONTROL_RESTRICTION' restriction through the instrumented system Bubblewrap path." \
    "The treatment comparison and capability subtraction would be based on an invalid startup, timeout, or unrelated failure." \
    "Resolve the control-path failure and rerun the complete Docker Desktop comparison." \
    "control probe evidence" "$control_evidence" "$PROBE_STATUS"
fi

run_probe treatment-full-candidates "${full_runtime_args[@]}"
if [[ $PROBE_STATUS -ne 0 ]]; then
  fail_with_output \
    "Codex runtime treatment failed with both unconfined options and all five candidate capabilities." \
    "Capability subtraction has no valid passing baseline." \
    "Resolve the supported Docker Desktop runtime or Codex sandbox failure, then rerun this test." \
    "treatment probe" "$PROBE_OUTPUT" "$PROBE_STATUS"
fi
if [[ -z "$PROBE_BWRAP_LOG" ]]; then
  fail_with_output \
    "Codex runtime treatment passed without invoking the instrumented system Bubblewrap wrapper." \
    "The result does not prove that Codex selected /usr/bin/bwrap instead of its bundled fallback." \
    "Restore system Bubblewrap selection and rerun this test." \
    "bwrap wrapper" "$PROBE_BWRAP_LOG" 1
fi

required=()
for omitted in "${CANDIDATES[@]}"; do
  omission_args=()
  for option in "${SECURITY_OPTIONS[@]}"; do
    omission_args+=(--security-opt "$option")
  done
  for capability in "${CANDIDATES[@]}"; do
    if [[ "$capability" != "$omitted" ]]; then
      omission_args+=(--cap-add "$capability")
    fi
  done

  run_probe "omit-$omitted" "${omission_args[@]}"
  omission_status=$PROBE_STATUS
  omission_output=$PROBE_OUTPUT
  omission_bwrap_log=$PROBE_BWRAP_LOG
  if [[ -z "$omission_bwrap_log" ]]; then
    omission_evidence="$(printf 'OUTPUT_BEGIN\n%s\nOUTPUT_END\nBWRAP_LOG_BEGIN\n%s\nBWRAP_LOG_END' \
      "$omission_output" "$omission_bwrap_log")"
    fail_with_output \
      "Codex runtime omission for '$omitted' did not invoke the instrumented system Bubblewrap path." \
      "Its status cannot determine whether '$omitted' is required by the intended Codex sandbox path." \
      "Restore system Bubblewrap selection and rerun the complete controlled subtraction." \
      "omission probe evidence" "$omission_evidence" "$omission_status"
  fi
  run_probe "restore-after-$omitted" "${full_runtime_args[@]}"
  if [[ $PROBE_STATUS -ne 0 ]]; then
    fail_with_output \
      "Codex runtime restoration failed after omitting capability '$omitted'." \
      "The omission result cannot be attributed to that single capability." \
      "Restore a stable Docker Desktop runtime and rerun the complete controlled comparison." \
      "restoration probe" "$PROBE_OUTPUT" "$PROBE_STATUS"
  fi
  if [[ -z "$PROBE_BWRAP_LOG" ]]; then
    fail_with_output \
      "Codex runtime restoration after '$omitted' passed without invoking the system Bubblewrap wrapper." \
      "The restoration does not validate the same Codex sandbox path as the treatment." \
      "Restore system Bubblewrap selection and rerun this test." \
      "bwrap wrapper" "$PROBE_BWRAP_LOG" 1
  fi
  if [[ $omission_status -ne 0 ]]; then
    required+=("$omitted")
  fi
done

final_args=()
for option in "${SECURITY_OPTIONS[@]}"; do
  final_args+=(--security-opt "$option")
done
for capability in "${required[@]}"; do
  final_args+=(--cap-add "$capability")
done
run_probe final-derived-set "${final_args[@]}"
if [[ $PROBE_STATUS -ne 0 ]]; then
  fail_with_output \
    "Codex runtime final derived capability set failed as a whole." \
    "The independently retained capabilities do not form a sufficient published runtime contract." \
    "Repeat the controlled subtraction and investigate capability interactions before changing the manifest." \
    "final probe" "$PROBE_OUTPUT" "$PROBE_STATUS"
fi
if [[ -z "$PROBE_BWRAP_LOG" ]]; then
  fail_with_output \
    "Codex runtime final derived set passed without invoking the system Bubblewrap wrapper." \
    "The final result does not prove Codex selected /usr/bin/bwrap." \
    "Restore system Bubblewrap selection and rerun this test." \
    "bwrap wrapper" "$PROBE_BWRAP_LOG" 1
fi

required_csv="$(IFS=,; printf '%s' "${required[*]}")"
printf 'REQUIRED_CAPABILITIES=%s\n' "$required_csv"
