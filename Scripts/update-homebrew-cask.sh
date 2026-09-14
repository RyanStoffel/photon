#!/usr/bin/env bash
# Bump Casks/photon.rb in RyanStoffel/homebrew-taps after a GitHub Release.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION:-$(tr -d '[:space:]' < "$ROOT/VERSION")}"
TAP_OWNER="${TAP_OWNER:-RyanStoffel}"
TAP_REPO="${TAP_REPO:-homebrew-taps}"
ASSET_URL="https://github.com/RyanStoffel/photon/releases/download/v${VERSION}/Photon-${VERSION}.zip"
SHA_FILE="$ROOT/dist/SHA256SUMS"

if [[ -z "${HOMEBREW_TAP_TOKEN:-}" ]]; then
  echo "HOMEBREW_TAP_TOKEN is not set; skipping cask bump."
  exit 0
fi

if [[ ! -f "$SHA_FILE" ]]; then
  echo "Missing $SHA_FILE" >&2
  exit 1
fi

SHA="$(awk '/Photon-.*\.zip$/ { print $1; exit }' "$SHA_FILE")"
if [[ -z "$SHA" ]]; then
  echo "Could not read zip sha256 from $SHA_FILE" >&2
  exit 1
fi

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

git clone --depth 1 "https://x-access-token:${HOMEBREW_TAP_TOKEN}@github.com/${TAP_OWNER}/${TAP_REPO}.git" "$WORK/tap"
CASK="$WORK/tap/Casks/photon.rb"

if [[ ! -f "$CASK" ]]; then
  mkdir -p "$WORK/tap/Casks"
  cat > "$CASK" <<EOF
cask "photon" do
  version "${VERSION}"
  sha256 "${SHA}"

  url "https://github.com/RyanStoffel/photon/releases/download/v#{version}/Photon-#{version}.zip"
  name "Photon"
  desc "Fast, minimal macOS launcher"
  homepage "https://github.com/RyanStoffel/photon"

  depends_on macos: :sonoma

  app "Photon.app"

  zap trash: [
    "~/Library/Application Support/Photon",
    "~/Library/Preferences/com.ryanstoffel.photon.plist",
  ]
end
EOF
else
  python3 - "$CASK" "$VERSION" "$SHA" <<'PY'
import re, sys
path, version, sha = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(path).read()
text, n1 = re.subn(r'version\s+"[^"]+"', f'version "{version}"', text, count=1)
text, n2 = re.subn(r'sha256\s+"[0-9a-fA-F]+"', f'sha256 "{sha}"', text, count=1)
if n1 != 1 or n2 != 1:
    raise SystemExit(f"Failed to patch cask (version={n1}, sha={n2})")
open(path, "w").write(text)
PY
fi

# Keep the download URL pointed at Photon-<version>.zip even if an older cask used a different name.
if ! grep -q 'Photon-#{version}.zip' "$CASK"; then
  echo "Warning: cask URL does not contain Photon-#{version}.zip; leaving URL as-is." >&2
fi

git -C "$WORK/tap" config user.name "photon-release[bot]"
git -C "$WORK/tap" config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git -C "$WORK/tap" add Casks/photon.rb
if git -C "$WORK/tap" diff --cached --quiet; then
  echo "Cask already at ${VERSION}; nothing to commit."
  exit 0
fi
git -C "$WORK/tap" commit -m "chore(photon): bump cask to ${VERSION}"
git -C "$WORK/tap" push origin HEAD
echo "Updated ${TAP_OWNER}/${TAP_REPO} Casks/photon.rb to ${VERSION}"
echo "unused asset url was ${ASSET_URL}" >/dev/null
