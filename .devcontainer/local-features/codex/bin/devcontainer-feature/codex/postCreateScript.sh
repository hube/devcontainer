#!/usr/bin/env bash
set -uo pipefail

errors=()
workdir=""

encode_diagnostic_output() {
  local output="$1"
  output="${output//$'\r'/\\r}"
  output="${output//$'\n'/\\n}"
  printf '%s' "$output"
}

cleanup() {
  if [[ -n "$workdir" ]]; then
    rm -rf "$workdir"
  fi
}
trap cleanup EXIT

bwrap_metadata="$(stat -c '%U:%G %a' /usr/bin/bwrap 2>&1)"
stat_status=$?
if [[ $stat_status -ne 0 ]]; then
  stat_detail="$(encode_diagnostic_output "${bwrap_metadata:-stat exited with status $stat_status without diagnostic output}")"
  errors+=("Codex Bubblewrap health check failed because Bubblewrap metadata could not be read. Codex sandbox startup cannot be verified. Ensure /usr/bin/bwrap exists and GNU stat can read it, then rerun the hook. stat said: $stat_detail")
elif [[ "$bwrap_metadata" != "root:root 4755" ]]; then
  stat_detail="$(encode_diagnostic_output "$bwrap_metadata")"
  errors+=("Codex Bubblewrap health check failed because /usr/bin/bwrap metadata was '$stat_detail', expected 'root:root 4755'. Codex sandbox startup is unsafe. Restore /usr/bin/bwrap to root:root with mode 4755, then rerun the hook. stat said: $stat_detail")
fi

mktemp_output="$(mktemp -d 2>&1)"
mktemp_status=$?
if [[ $mktemp_status -ne 0 ]]; then
  mktemp_detail="$(encode_diagnostic_output "${mktemp_output:-mktemp exited with status $mktemp_status without diagnostic output}")"
  errors+=("Codex sandbox health check failed because a temporary workspace could not be created. Codex sandbox availability cannot be verified. Ensure the container user can create temporary directories, then rerun the hook. mktemp said: $mktemp_detail")
else
  workdir="$mktemp_output"
  probe_output="$(timeout 30s codex sandbox -P :workspace -C "$workdir" \
    bash -c "printf '%s\\n' codex-sandbox-ok > codex-sandbox-marker && cat codex-sandbox-marker" 2>&1)"
  probe_status=$?

  marker_output=""
  if [[ -r "$workdir/codex-sandbox-marker" ]]; then
    marker_output="$(<"$workdir/codex-sandbox-marker")"
  fi

  sentinel_seen=false
  while IFS= read -r output_line; do
    if [[ "$output_line" == "codex-sandbox-ok" ]]; then
      sentinel_seen=true
    fi
  done <<<"$probe_output"

  probe_problem=""
  if [[ $probe_status -ne 0 ]]; then
    probe_problem="the Codex sandbox probe exited with status $probe_status"
  elif [[ "$sentinel_seen" != true ]]; then
    probe_problem="the Codex sandbox probe did not print codex-sandbox-ok"
  elif [[ "$marker_output" != "codex-sandbox-ok" ]]; then
    probe_problem="the Codex sandbox probe did not create and read codex-sandbox-marker"
  fi

  if [[ -n "$probe_problem" ]]; then
    probe_detail="$(encode_diagnostic_output "${probe_output:-probe exited with status $probe_status without diagnostic output}")"
    errors+=("Codex sandbox health check failed because $probe_problem. Codex sandbox availability cannot be verified. Ensure Codex and GNU timeout are installed and sandboxing can create files in the workspace, then rerun the hook. codex sandbox said: $probe_detail")
  fi
fi

if ((${#errors[@]})); then
  printf '%s\n' "${errors[@]}" >&2
  exit 1
fi
