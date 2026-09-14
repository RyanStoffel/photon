#!/usr/bin/env bash
# Build Photon.app from the Swift package. Ad-hoc signs the bundle.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="$(tr -d '[:space:]' < VERSION)"
APP="$ROOT/build/Photon.app"
CONTENTS="$APP/Contents"

swift build -c release --package-path "$ROOT"
BIN_DIR="$(swift build -c release --package-path "$ROOT" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BIN_DIR/Photon" "$CONTENTS/MacOS/Photon"
cp "$ROOT/Resources/Photon.icns" "$CONTENTS/Resources/Photon.icns"
sed "s/VERSION_PLACEHOLDER/${VERSION}/g" "$ROOT/Resources/Info.plist" > "$CONTENTS/Info.plist"
chmod +x "$CONTENTS/MacOS/Photon"

if [[ "$(uname -s)" == "Darwin" ]]; then
  plutil -lint "$CONTENTS/Info.plist" >/dev/null
  codesign --force --deep --sign - "$APP"
fi

printf '%s\n' "$APP"
