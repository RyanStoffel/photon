#!/usr/bin/env bash
# Re-sign Photon.app (Developer ID + notarize when secrets exist; otherwise keep ad-hoc)
# and write dist/Photon-<version>.zip, dist/Photon-<version>.dmg, dist/SHA256SUMS.
#
# Outputs `signing=adhoc|developer-id|developer-id-notarized` (also to $GITHUB_OUTPUT).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${VERSION:-$(tr -d '[:space:]' < VERSION)}"
APP="$ROOT/build/Photon.app"
DIST="$ROOT/dist"
IDENTITY=""
SIGNING="adhoc"

if [[ ! -d "$APP" ]]; then
  echo "Missing $APP — run Scripts/package_app.sh first." >&2
  exit 1
fi

mkdir -p "$DIST"

if [[ -n "${MACOS_CERTIFICATE_P12:-}" && -n "${MACOS_CERTIFICATE_PASSWORD:-}" ]]; then
  KEYCHAIN="photon-signing.keychain-db"
  KEYCHAIN_PASSWORD="$(openssl rand -base64 24)"
  CERT_PATH="$(mktemp)"
  printf '%s' "$MACOS_CERTIFICATE_P12" | base64 --decode > "$CERT_PATH"

  security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
  security set-keychain-settings -lut 21600 "$KEYCHAIN"
  security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
  security import "$CERT_PATH" -P "$MACOS_CERTIFICATE_PASSWORD" -A -t cert -f pkcs12 -k "$KEYCHAIN"
  security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
  security list-keychain -d user -s "$KEYCHAIN" "$(security list-keychain -d user | tr -d '"')"

  IDENTITY="$(security find-identity -v -p codesigning "$KEYCHAIN" | awk -F'\"' '/Developer ID Application/ { print $2; exit }')"
  rm -f "$CERT_PATH"

  if [[ -z "$IDENTITY" ]]; then
    echo "Certificate imported but no Developer ID Application identity was found." >&2
    exit 1
  fi

  codesign --force --deep --options runtime --timestamp \
    --entitlements "$ROOT/Resources/Photon.entitlements" \
    --sign "$IDENTITY" "$APP"
  SIGNING="developer-id"

  if [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]]; then
    ZIP="$DIST/Photon-${VERSION}-notarize.zip"
    ditto -c -k --keepParent "$APP" "$ZIP"
    xcrun notarytool submit "$ZIP" \
      --apple-id "$APPLE_ID" \
      --team-id "$APPLE_TEAM_ID" \
      --password "$APPLE_APP_SPECIFIC_PASSWORD" \
      --wait
    xcrun stapler staple "$APP"
    rm -f "$ZIP"
    SIGNING="developer-id-notarized"
  else
    echo "::warning::Developer ID certificate present but APPLE_ID / APPLE_TEAM_ID / APPLE_APP_SPECIFIC_PASSWORD are missing; signed without notarizing."
  fi
else
  echo "::notice::MACOS_CERTIFICATE_P12 / MACOS_CERTIFICATE_PASSWORD are not set; ad-hoc signing Photon.app. The release notes will say so."
  codesign --force --deep --sign - "$APP"
fi

codesign --verify --deep --strict "$APP"

ZIP="$DIST/Photon-${VERSION}.zip"
DMG="$DIST/Photon-${VERSION}.dmg"
rm -f "$ZIP" "$DMG" "$DIST/SHA256SUMS"

ditto -c -k --keepParent "$APP" "$ZIP"

STAGING="$(mktemp -d)"
cp -R "$APP" "$STAGING/Photon.app"
hdiutil create -volname "Photon" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"

(
  cd "$DIST"
  shasum -a 256 "Photon-${VERSION}.zip" "Photon-${VERSION}.dmg" > SHA256SUMS
)

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "signing=$SIGNING" >> "$GITHUB_OUTPUT"
fi

echo "signing=$SIGNING"
echo "$ZIP"
echo "$DMG"
