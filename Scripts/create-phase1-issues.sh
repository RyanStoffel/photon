#!/usr/bin/env bash
# Create the Phase 1 product + infra issues. Requires gh auth and labels.
set -euo pipefail

OWNER="${1:-RyanStoffel}"
REPO="${2:-photon}"

create() {
  local title="$1"
  local labels="$2"
  local body="$3"
  gh issue create --repo "${OWNER}/${REPO}" --title "$title" --label "$labels" --body "$body"
}

create "Launcher hotkey (Cmd+Space) with Spotlight conflict guidance" \
  "type/feature,area/launcher,priority/p1" \
  "$(cat <<'EOF'
## Summary

Photon opens from a global hotkey. The default is Cmd+Space. Detect a Spotlight shortcut collision on first launch and tell the user how to disable Spotlight's shortcut. The hotkey is configurable from Settings > General.

## Acceptance criteria

- [ ] Cmd+Space (or the configured combo) toggles the launcher while Photon is running as a menu-bar agent
- [ ] The hotkey is registered through a `HotkeyManager` that wraps Carbon `RegisterEventHotKey`
- [ ] First launch detects `com.apple.symbolichotkeys` id 64 matching Photon's shortcut and shows guidance
- [ ] Settings > General can record a new shortcut and the manager re-registers it
EOF
)"

create "Launch applications via fuzzy search and frecency" \
  "type/feature,area/launcher,priority/p1" \
  "$(cat <<'EOF'
## Summary

The launcher indexes applications and System Settings panes, ranks them with fuzzy matching plus frecency, and launches the selection with `NSWorkspace`.

## Acceptance criteria

- [ ] Indexes `/Applications`, `/System/Applications`, `~/Applications`, and `.prefPane` bundles
- [ ] Fuzzy matcher is case-insensitive subsequence search with unit tests
- [ ] Frecency store persists under Application Support and has unit tests
- [ ] Enter / click launches via `NSWorkspace`
- [ ] Results appear in the floating launcher panel with keyboard navigation
EOF
)"

create "Clipboard history" \
  "type/feature,area/clipboard,priority/p1" \
  "$(cat <<'EOF'
## Summary

Phase 2. Searchable clipboard history for text, links, images, and files, with pin, paste/copy-back, retention, and excluded apps (password managers).

## Acceptance criteria

- [ ] Implemented in `Sources/PhotonClipboard/` as a `CommandProvider`
- [ ] Registered from `AppRuntime` only
- [ ] Settings > Clipboard is wired to real controls
- [ ] Password managers can be excluded
EOF
)"

create "Simple notes" \
  "type/feature,area/notes,priority/p1" \
  "$(cat <<'EOF'
## Summary

Phase 2. Raycast Notes-like floating notes: lightweight markdown, multiple notes, persistent, searchable from the launcher.

## Acceptance criteria

- [ ] Implemented in `Sources/PhotonNotes/` as a `CommandProvider`
- [ ] Notes persist locally
- [ ] Searchable from the launcher
- [ ] Settings > Notes is wired to real controls
EOF
)"

create "File search" \
  "type/feature,area/files,priority/p1" \
  "$(cat <<'EOF'
## Summary

Phase 2. Whole-Mac search via Spotlight (`NSMetadataQuery`), Quick Look, open / reveal in Finder / copy path.

## Acceptance criteria

- [ ] Implemented in `Sources/PhotonFiles/` as a `CommandProvider`
- [ ] Backed by `NSMetadataQuery`, not a custom crawler
- [ ] Open, reveal in Finder, and copy path work
- [ ] Settings > Files is wired to real controls
EOF
)"

create "Keybinds and window management" \
  "type/feature,area/keybinds,priority/p1" \
  "$(cat <<'EOF'
## Summary

Phase 2. Configurable Hyper key (default Caps Lock → Ctrl+Opt+Shift+Cmd), user-defined hotkeys to launch or focus apps, and window management (halves, thirds, maximize, center, next display) via the Accessibility API.

## Acceptance criteria

- [ ] Implemented in `Sources/PhotonKeybinds/`
- [ ] Hyper key can be enabled/disabled
- [ ] App launch/focus hotkeys work
- [ ] Window commands work on the frontmost window
- [ ] Settings > Keybinds is wired to real controls
- [ ] Accessibility permission is requested with a clear explanation
EOF
)"

create "Settings window" \
  "type/feature,area/settings,priority/p1" \
  "$(cat <<'EOF'
## Summary

Native settings window with tabs: General, Clipboard, Notes, Files, Keybinds, About. Phase 1 ships General (hotkey + launch at login) and About. Other tabs are placeholders bound to `SettingsStore`.

## Acceptance criteria

- [ ] Settings window opens from the menu bar extra
- [ ] General: hotkey recorder and launch-at-login via `SMAppService`
- [ ] About: version from `VERSION` / `PhotonVersion`, bundle id, license
- [ ] Placeholder tabs read and write `SettingsStore` keys
EOF
)"

create "CI pipeline" \
  "type/infra,area/ci,priority/p1" \
  "$(cat <<'EOF'
## Summary

GitHub Actions CI on PRs and pushes to `develop` / `main`: branch-name check, SwiftLint + SwiftFormat, Release build, unit tests, upload `Photon.app`. Jobs are the required status checks.

## Acceptance criteria

- [ ] `.github/workflows/ci.yml` exists
- [ ] Jobs named `branch-name`, `lint`, `build`, `test`
- [ ] `Photon.app` is uploaded as an artifact
- [ ] SwiftPM `.build` is cached
- [ ] Required on `develop` and `main`
EOF
)"

create "Release pipeline" \
  "type/infra,area/release,priority/p1" \
  "$(cat <<'EOF'
## Summary

Tag `v*.*.*` builds a Release, signs/notarizes when Apple secrets exist (otherwise ad-hoc), publishes `Photon-<version>.zip`, `Photon-<version>.dmg`, `SHA256SUMS`, and a GitHub Release. Does not cut a release in Phase 1.

## Acceptance criteria

- [ ] `.github/workflows/release.yml` runs on `v*.*.*`
- [ ] Tag must match the `VERSION` file
- [ ] Ad-hoc path is documented in release notes when secrets are missing
- [ ] `docs/releasing.md` lists secrets and the procedure
- [ ] `Scripts/bump-version.sh` is the only way to change the version string
EOF
)"

create "Homebrew cask in ryanstoffel/taps" \
  "type/infra,area/release,priority/p1" \
  "$(cat <<'EOF'
## Summary

The release workflow bumps `Casks/photon.rb` in [RyanStoffel/homebrew-taps](https://github.com/RyanStoffel/homebrew-taps) when `HOMEBREW_TAP_TOKEN` is set. Install line: `brew install --cask ryanstoffel/taps/photon`.

## Acceptance criteria

- [ ] Cask token is `photon`
- [ ] URL is `Photon-#{version}.zip` from the GitHub Release
- [ ] `Scripts/update-homebrew-cask.sh` updates version + sha256
- [ ] Missing tap token skips the bump without failing the release
EOF
)"

create "Developer ID signing and notarization" \
  "type/infra,area/release,priority/p2" \
  "$(cat <<'EOF'
## Summary

Ryan supplies Apple secrets. When they are present, the release workflow signs with Developer ID, notarizes, and staples. Until then, builds are ad-hoc signed.

## Acceptance criteria

- [ ] Secrets documented in `docs/releasing.md`
- [ ] `Scripts/sign-and-package.sh` uses them when set
- [ ] Release notes state the signing mode
- [ ] Ryan has added the secrets (blocked on Ryan)
EOF
)"
