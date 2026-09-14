#!/usr/bin/env bash
# Print the GitHub Release notes for a version to stdout.
#
# The body is the matching `## [<version>]` section of CHANGELOG.md. When the
# section is missing the script falls back to GitHub's generated notes (needs
# GH_TOKEN and GITHUB_REPOSITORY) and says so. A signing section and install
# instructions are always appended.
#
# Usage: VERSION=0.1.0 SIGNING=adhoc|developer-id|developer-id-notarized Scripts/release-notes.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION:-$(tr -d '[:space:]' < "$ROOT/VERSION")}"
SIGNING="${SIGNING:-adhoc}"
CHANGELOG="${CHANGELOG:-$ROOT/CHANGELOG.md}"
REPO="${GITHUB_REPOSITORY:-RyanStoffel/photon}"

changelog_section() {
  [[ -f "$CHANGELOG" ]] || return 1
  awk -v version="$VERSION" '
    /^## / {
      if (printing) exit
      if (index($0, "## [" version "]") == 1) { printing = 1; next }
    }
    printing { print }
  ' "$CHANGELOG" \
    | grep -vE '^\[(Unreleased|[0-9]+\.[0-9]+\.[0-9]+)\]: ' \
    | sed '/./,$!d' | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}'
}

body="$(changelog_section || true)"

if [[ -n "$body" ]]; then
  printf '%s\n' "$body"
else
  echo "CHANGELOG.md has no section for ${VERSION}; using generated notes." >&2
  generated=""
  if [[ -n "${GH_TOKEN:-}" ]]; then
    generated="$(gh api "repos/${REPO}/releases/generate-notes" \
      -f tag_name="v${VERSION}" \
      -f target_commitish="${GITHUB_SHA:-HEAD}" \
      --jq .body 2>/dev/null || true)"
  fi
  if [[ -n "$generated" ]]; then
    printf '%s\n' "$generated"
  else
    echo "Photon ${VERSION}."
  fi
fi

cat <<EOF

## Signing

EOF

case "$SIGNING" in
  developer-id-notarized)
    echo "This build is signed with a Developer ID certificate, notarized by Apple, and stapled. It opens without Gatekeeper warnings."
    ;;
  developer-id)
    echo "This build is signed with a Developer ID certificate but was not notarized (the notarization secrets were not configured). macOS may still warn on first launch; open **System Settings > Privacy & Security** and click **Open Anyway**."
    ;;
  *)
    cat <<'EOF'
This build is **ad-hoc signed** and **not notarized**: the Apple signing secrets were not configured when it was built. macOS Gatekeeper will block the first launch of a downloaded copy.

- macOS 14: Control-click `Photon.app` and choose **Open**, then confirm.
- macOS 15 and later: try to open the app once, then open **System Settings > Privacy & Security** and click **Open Anyway**.
- Or remove the quarantine flag: `xattr -dr com.apple.quarantine /Applications/Photon.app`
EOF
    ;;
esac

cat <<EOF

## Install

\`\`\`sh
brew tap ryanstoffel/taps
brew install --cask ryanstoffel/taps/photon
\`\`\`

On Homebrew 7 or later, run \`brew trust ryanstoffel/taps\` once so that \`brew upgrade\` can load the cask.

Or download \`Photon-${VERSION}.zip\` (or the \`.dmg\`) below and move \`Photon.app\` to \`/Applications\`. Verify a download with \`shasum -a 256 -c SHA256SUMS\` after placing the file next to it.

Photon needs macOS 14 or later. It asks for Accessibility access on first launch for paste-back, the Hyper key, and window management; everything else works without it.
EOF
