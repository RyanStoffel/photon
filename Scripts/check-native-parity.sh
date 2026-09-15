#!/usr/bin/env bash
# Launch the packaged app on macOS and exercise native panel, process, hotkey,
# appearance, clipboard, frame, and icon behavior.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "check-native-parity.sh only runs on macOS." >&2
  exit 2
fi

APP="${1:-$ROOT/build/Photon.app}"
if [[ ! -d "$APP" ]]; then
  Scripts/package_app.sh
fi
APP="$(cd "$APP" && pwd)"

PLIST="$APP/Contents/Info.plist"
EXECUTABLE="$APP/Contents/MacOS/Photon"
[[ -x "$EXECUTABLE" ]] || { echo "Missing Photon executable: $EXECUTABLE" >&2; exit 1; }
[[ "$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$PLIST")" == "true" ]] || {
  echo "Photon.app must set LSUIElement=true." >&2
  exit 1
}

DATA_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/photon-native-parity.XXXXXX")"
REPORT="$DATA_ROOT/native-report.json"
COMMAND="$DATA_ROOT/native-command"
APP_LOG="$DATA_ROOT/photon.log"
SCREENSHOT_DIR="${NATIVE_PARITY_SCREENSHOT_DIR:-$DATA_ROOT/screenshots}"
SEED_FILE="$HOME/Documents/Photon Native Parity/Ember_Individual_Pitch.pdf"
SEED_IMAGE="$HOME/Documents/Photon Native Parity/Photon_Recent_Image.png"
GRANT_DIR="$(dirname "$SEED_FILE")"
GRANT_FILE="$GRANT_DIR/Photon_Bookmark_Ember_Proof.pdf"
GRANT_QUERY="bookmark ember proof"
SEED_CREATED=0
SEED_IMAGE_CREATED=0
PID=""

restore() {
  if [[ -n "$PID" ]] && kill -0 "$PID" 2>/dev/null; then
    kill -TERM "$PID" 2>/dev/null || true
  fi
  pkill -x Photon 2>/dev/null || true
  defaults delete -g AppleInterfaceStyle 2>/dev/null || true
  killall cfprefsd 2>/dev/null || true
  if [[ "$SEED_CREATED" == "1" ]]; then
    rm -f "$SEED_FILE"
  fi
  rm -f "$GRANT_FILE"
  if [[ "$SEED_IMAGE_CREATED" == "1" ]]; then
    rm -f "$SEED_IMAGE"
  fi
  if [[ "${KEEP_PARITY_ARTIFACTS:-0}" != "1" ]]; then
    rm -rf "$DATA_ROOT"
  else
    echo "Parity artifacts: $DATA_ROOT"
  fi
}
trap restore EXIT

pkill -x Photon 2>/dev/null || true
defaults delete -g AppleInterfaceStyle 2>/dev/null || true
killall cfprefsd 2>/dev/null || true
sleep 1

mkdir -p "$(dirname "$SEED_FILE")" "$SCREENSHOT_DIR"
SEED_CREATED=1
SEED_IMAGE_CREATED=1
swift "$ROOT/Scripts/create-preview-fixtures.swift" "$SEED_FILE" "$SEED_IMAGE"
/usr/bin/mdimport "$SEED_FILE" >/dev/null 2>&1 || true
/usr/bin/mdimport "$SEED_IMAGE" >/dev/null 2>&1 || true
mkdir -p "$GRANT_DIR"
printf 'Photon guided file access fixture\n' >"$GRANT_FILE"

PHOTON_NATIVE_PARITY_REPORT_PATH="$REPORT" \
PHOTON_NATIVE_PARITY_COMMAND_PATH="$COMMAND" \
PHOTON_ISOLATED_DATA_ROOT="$DATA_ROOT/data" \
PHOTON_NATIVE_PARITY_FILE_ACCESS_SELECTION="$GRANT_DIR" \
PHOTON_NATIVE_PARITY_FILE_ACCESS_QUERY="$GRANT_QUERY" \
PHOTON_NATIVE_PARITY_FILE_ACCESS_RESULT="$(basename "$GRANT_FILE")" \
PHOTON_NATIVE_PARITY_RECENT_FILES="$SEED_FILE:$SEED_IMAGE" \
PHOTON_APPLICATIONS_EXTRA="/Applications:/System/Applications" \
  "$EXECUTABLE" >"$APP_LOG" 2>&1 &
PID=$!

swift "$ROOT/Scripts/native-macos-parity.swift" "$REPORT" "$COMMAND" "$SCREENSHOT_DIR" || {
  echo "--- Photon runtime log ---" >&2
  cat "$APP_LOG" >&2
  echo "--- Native report ---" >&2
  if [[ -f "$REPORT" ]]; then
    cat "$REPORT" >&2
  fi
  exit 1
}

kill -0 "$PID" 2>/dev/null || {
  echo "Photon exited during native parity checks." >&2
  cat "$APP_LOG" >&2
  exit 1
}

kill -TERM "$PID"
wait "$PID" 2>/dev/null || true
PID=""
rm -f "$REPORT" "$COMMAND"
PHOTON_NATIVE_PARITY_REPORT_PATH="$REPORT" \
PHOTON_NATIVE_PARITY_COMMAND_PATH="$COMMAND" \
PHOTON_ISOLATED_DATA_ROOT="$DATA_ROOT/data" \
PHOTON_NATIVE_PARITY_FILE_ACCESS_SELECTION="$GRANT_DIR" \
PHOTON_NATIVE_PARITY_FILE_ACCESS_QUERY="$GRANT_QUERY" \
PHOTON_NATIVE_PARITY_FILE_ACCESS_RESULT="$(basename "$GRANT_FILE")" \
PHOTON_APPLICATIONS_EXTRA="/Applications:/System/Applications" \
  "$EXECUTABLE" >>"$APP_LOG" 2>&1 &
PID=$!

swift "$ROOT/Scripts/native-macos-parity.swift" "$REPORT" "$COMMAND" "$SCREENSHOT_DIR" relaunch || {
  echo "--- Photon relaunch runtime log ---" >&2
  cat "$APP_LOG" >&2
  echo "--- Native relaunch report ---" >&2
  if [[ -f "$REPORT" ]]; then
    cat "$REPORT" >&2
  fi
  exit 1
}

kill -0 "$PID" 2>/dev/null || {
  echo "Photon exited during file-access relaunch checks." >&2
  cat "$APP_LOG" >&2
  exit 1
}

echo "Native macOS runtime parity green for $APP"
echo "Native parity screenshots: $SCREENSHOT_DIR"
