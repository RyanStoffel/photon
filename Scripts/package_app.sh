#!/usr/bin/env bash
# Build Photon.app from the Swift package. Ad-hoc signs the bundle.
#
# Set PHOTON_ARCHS="arm64 x86_64" to build a universal binary (the release
# workflow does). By default SwiftPM builds for the host architecture only.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="$(tr -d '[:space:]' < VERSION)"
APP="$ROOT/build/Photon.app"
CONTENTS="$APP/Contents"

BUILD_ARGS=(-c release --package-path "$ROOT")
for arch in ${PHOTON_ARCHS:-}; do
  BUILD_ARGS+=(--arch "$arch")
done

swift build "${BUILD_ARGS[@]}"
BIN_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"

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
