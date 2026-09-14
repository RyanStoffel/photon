#!/usr/bin/env bash
# Build Photon and capture UI scenario screenshots (macOS only).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "screenshots.sh only runs on macOS." >&2
  exit 1
fi

APP="$ROOT/build/Photon.app"
OUT="$ROOT/docs/screenshots"
HELPER="$ROOT/Scripts/photon-window-id.swift"
SCENARIOS=(
  launcher-empty
  launcher-query:saf
  settings:appearance
  notes
)

Scripts/package_app.sh

mkdir -p "$OUT"

slug_for() {
  local scenario="$1"
  echo "${scenario//:/-}"
}

wait_for_ready() {
  local marker="$1"
  local deadline=$((SECONDS + 45))
  while (( SECONDS < deadline )); do
    if [[ -f "$marker" ]] && [[ "$(cat "$marker")" == "ready" ]]; then
      return 0
    fi
    sleep 0.25
  done
  echo "Timed out waiting for UI scenario ready marker: $marker" >&2
  return 1
}

window_ids_for_pid() {
  local pid="$1"
  swift "$HELPER" --pid "$pid" --owner Photon --layer 0 2>/dev/null || true
}

capture_pid_windows() {
  local pid="$1"
  local destination="$2"
  local ids
  ids="$(window_ids_for_pid "$pid")"
  if [[ -z "$ids" ]]; then
    echo "No Photon windows found for pid $pid" >&2
    return 1
  fi
  local index=0
  while IFS= read -r window_id; do
    [[ -z "$window_id" ]] && continue
    local path="$destination"
    if (( index > 0 )); then
      path="${destination%.png}-${index}.png"
    fi
    screencapture -x -l "$window_id" "$path"
    sips -Z 1600 "$path" >/dev/null
    index=$((index + 1))
  done <<< "$ids"
  if (( index == 0 )); then
    return 1
  fi
  return 0
}

quit_photon() {
  pkill -x Photon 2>/dev/null || true
  sleep 1
  pkill -9 -x Photon 2>/dev/null || true
}

set_appearance() {
  local mode="$1"
  if [[ "$mode" == "dark" ]]; then
    defaults write -g AppleInterfaceStyle Dark
  else
    defaults delete -g AppleInterfaceStyle 2>/dev/null || true
  fi
  killall cfprefsd 2>/dev/null || true
  sleep 0.5
}

run_scenario() {
  local scenario="$1"
  local appearance="$2"
  local slug
  slug="$(slug_for "$scenario")"
  local png="$OUT/${slug}-${appearance}.png"
  local data_root
  data_root="$(mktemp -d "${TMPDIR:-/tmp}/photon-ui-data.XXXXXX")"
  local ready_marker="$data_root/ready"
  rm -f "$png"

  quit_photon

  PHOTON_UI_SCENARIO="$scenario" \
  PHOTON_ISOLATED_DATA_ROOT="$data_root" \
  PHOTON_UI_SCENARIO_READY_PATH="$ready_marker" \
  PHOTON_APPLICATIONS_EXTRA="/Applications:/System/Applications" \
    "$APP/Contents/MacOS/Photon" &
  local pid=$!

  wait_for_ready "$ready_marker"
  sleep 0.75

  capture_pid_windows "$pid" "$png" || {
    quit_photon
    rm -rf "$data_root"
    return 1
  }

  quit_photon
  rm -rf "$data_root"
  printf 'Wrote %s\n' "$png"
}

for appearance in light dark; do
  set_appearance "$appearance"
  for scenario in "${SCENARIOS[@]}"; do
    run_scenario "$scenario" "$appearance"
  done
done

echo "Screenshots written to $OUT"
