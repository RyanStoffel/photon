#!/usr/bin/env bash
# Launch Photon.app through LaunchServices, keep it running for a few seconds, and
# fail if the process exited, macOS wrote a crash report for it, or the unified log
# recorded a Swift fatal error or an uncaught Objective-C exception. This is the only
# runtime check that runs in CI.
#
# Usage: Scripts/smoke-test.sh [path/to/Photon.app]
# Env:   SMOKE_WAIT_SECONDS (default 8), SMOKE_LOG (unified log excerpt destination)
set -euo pipefail

APP="${1:-build/Photon.app}"
WAIT_SECONDS="${SMOKE_WAIT_SECONDS:-8}"
LOG_OUT="${SMOKE_LOG:-${TMPDIR:-/tmp}/photon-smoke.log}"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "smoke-test.sh only runs on macOS." >&2
  exit 2
fi

if [[ ! -d "$APP" ]]; then
  echo "Missing app bundle: $APP" >&2
  exit 1
fi

APP="$(cd "$APP" && pwd)"
EXECUTABLE="$APP/Contents/MacOS/Photon"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")"
REPORT_DIRS=("$HOME/Library/Logs/DiagnosticReports" "/Library/Logs/DiagnosticReports")

fail() {
  echo "::error::$*" >&2
  echo "SMOKE TEST FAILED: $*" >&2
  exit 1
}

list_reports() {
  local dir
  for dir in "${REPORT_DIRS[@]}"; do
    find "$dir" -maxdepth 1 \( -name 'Photon*.ips' -o -name 'Photon*.crash' \) 2>/dev/null || true
  done | sort
}

dump_log() {
  if [[ -s "$LOG_OUT" ]]; then
    echo "--- unified log for $BUNDLE_ID (last $(wc -l < "$LOG_OUT" | tr -d ' ') lines) ---"
    tail -n 80 "$LOG_OUT"
    echo "--- end of log ---"
  fi
}

collect_log() {
  # `log show` occasionally exits non-zero when the store rotates; keep whatever it produced.
  log show --style compact --info \
    --start "$STARTED_AT" \
    --predicate "process == \"Photon\" OR subsystem == \"$BUNDLE_ID\"" \
    > "$LOG_OUT" 2>/dev/null || true
}

[[ -x "$EXECUTABLE" ]] || fail "$EXECUTABLE is missing or not executable"
plutil -lint "$APP/Contents/Info.plist" >/dev/null || fail "Info.plist does not parse"
codesign --verify --deep --strict "$APP" || fail "code signature does not verify"

echo "Bundle:     $APP"
echo "Bundle id:  $BUNDLE_ID"
echo "Version:    $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
echo "Archs:      $(lipo -archs "$EXECUTABLE")"
echo "Signature:  $(codesign -dv "$APP" 2>&1 | awk -F= '/^Signature=|^Authority=/ { print $2; exit }')"
echo "macOS:      $(sw_vers -productVersion) ($(uname -m))"

# A stale instance would make `open` activate it instead of launching this bundle.
pkill -x Photon 2>/dev/null || true
sleep 1

BEFORE="$(list_reports)"
STARTED_AT="$(date '+%Y-%m-%d %H:%M:%S')"

echo "Launching with open(1)..."
open "$APP" || fail "open(1) refused to launch the bundle"

PID=""
for _ in $(seq 1 100); do
  PID="$(pgrep -x Photon | head -n 1 || true)"
  if [[ -n "$PID" ]]; then
    break
  fi
  sleep 0.1
done
[[ -n "$PID" ]] || { collect_log; dump_log; fail "no Photon process appeared within 10 s"; }

canonical() {
  (cd "$(dirname "$1")" && printf '%s/%s\n' "$(pwd -P)" "$(basename "$1")")
}
RUNNING_EXECUTABLE="$(ps -p "$PID" -o comm= | sed 's/^ *//')"
if [[ "$(canonical "$RUNNING_EXECUTABLE")" != "$(canonical "$EXECUTABLE")" ]]; then
  fail "pid $PID is running $RUNNING_EXECUTABLE, expected $EXECUTABLE"
fi

echo "Photon is running (pid $PID). Waiting ${WAIT_SECONDS}s..."
sleep "$WAIT_SECONDS"

STATUS=0
if ! kill -0 "$PID" 2>/dev/null; then
  echo "::error::Photon (pid $PID) exited within ${WAIT_SECONDS}s"
  STATUS=1
elif [[ "$(ps -p "$PID" -o stat= | tr -d ' ')" == Z* ]]; then
  echo "::error::Photon (pid $PID) is a zombie"
  STATUS=1
else
  echo "Photon is still alive after ${WAIT_SECONDS}s."
fi

# Crash reports are written asynchronously by ReportCrash; give it a moment.
sleep 2
NEW_REPORTS="$(comm -13 <(printf '%s\n' "$BEFORE") <(list_reports) || true)"
if [[ -n "$NEW_REPORTS" ]]; then
  echo "::error::macOS wrote a crash report for Photon:"
  while IFS= read -r report; do
    echo "--- $report ---"
    head -n 60 "$report" || true
  done <<<"$NEW_REPORTS"
  STATUS=1
fi

collect_log
# AppKit swallows uncaught exceptions on the main run loop, so the process survives them
# while whatever was running (for example AppRuntime.start) silently stops. Treat them as failures.
FATAL_PATTERN='Fatal error|EXC_BAD_ACCESS|EXC_CRASH|Termination Reason|An uncaught exception was raised|HIExceptions\] FAULT'
if grep -Eq "$FATAL_PATTERN" "$LOG_OUT"; then
  echo "::error::the unified log contains a fatal error or uncaught exception for Photon"
  grep -En "$FATAL_PATTERN" "$LOG_OUT" | head -n 20
  STATUS=1
fi

if kill -0 "$PID" 2>/dev/null; then
  kill -TERM "$PID" 2>/dev/null || true
  for _ in $(seq 1 50); do
    kill -0 "$PID" 2>/dev/null || break
    sleep 0.1
  done
  kill -KILL "$PID" 2>/dev/null || true
fi

if [[ "$STATUS" -ne 0 ]]; then
  dump_log
  echo "SMOKE TEST FAILED" >&2
  exit "$STATUS"
fi

echo "Smoke test passed: Photon launched, stayed alive for ${WAIT_SECONDS}s, and left no crash report."
echo "Log excerpt: $LOG_OUT ($(wc -l < "$LOG_OUT" | tr -d ' ') lines)"
