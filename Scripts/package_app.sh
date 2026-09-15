#!/usr/bin/env bash
# Build Photon.app from the Rust package. Ad-hoc signs the bundle.
#
# Set PHOTON_ARCHS="arm64 x86_64" to build a universal binary (the release
# workflow does). By default cargo builds for the host architecture only.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="$(tr -d '[:space:]' < VERSION)"
APP="$ROOT/build/Photon.app"
CONTENTS="$APP/Contents"
BIN="$CONTENTS/MacOS/Photon"

mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

HOST_ARCH="$(uname -m)"
ARCHS="${PHOTON_ARCHS:-}"

if [[ -z "$ARCHS" ]]; then
  cargo build --release -p photon
  rm -rf "$APP"
  mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
  cp "$ROOT/target/release/photon" "$BIN"
else
  BINS=()
  for arch in $ARCHS; do
    case "$arch" in
      arm64) rust_target="aarch64-apple-darwin" ;;
      x86_64) rust_target="x86_64-apple-darwin" ;;
      *) echo "unknown arch $arch" >&2; exit 1 ;;
    esac
    rustup target add "$rust_target" >/dev/null
    cargo build --release -p photon --target "$rust_target"
    BINS+=("$ROOT/target/${rust_target}/release/photon")
  done
  rm -rf "$APP"
  mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
  if [[ ${#BINS[@]} -eq 1 ]]; then
    cp "${BINS[0]}" "$BIN"
  else
    lipo -create "${BINS[@]}" -output "$BIN"
  fi
fi

cp "$ROOT/Resources/Photon.icns" "$CONTENTS/Resources/Photon.icns"
sed "s/VERSION_PLACEHOLDER/${VERSION}/g" "$ROOT/Resources/Info.plist" > "$CONTENTS/Info.plist"
chmod +x "$BIN"

if [[ "$(uname -s)" == "Darwin" ]]; then
  plutil -lint "$CONTENTS/Info.plist" >/dev/null
  codesign --force --deep --sign - "$APP"
fi

printf '%s\n' "$APP"
