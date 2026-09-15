# Photon

<p align="center">
  <img src="docs/assets/icon.png" width="128" height="128" alt="Photon icon">
</p>

Photon is a stripped-down, macOS-only launcher. It opens instantly, stays out of the Dock, and covers the few things that actually get used: applications, clipboard history, notes, file search, and keybinds.

It is not an extension platform. There is no AI, no account, no cloud sync, and no telemetry.

Photon is written in **Rust** and drawn with **GPUI** (Zed's GPU UI). The Swift/SwiftUI app is no longer what we ship.

## Features

- **Launcher** — `Cmd+Space` opens a compact floating search field that expands into results as you type. Down on the empty bar shows recommended apps and recents; turn on suggestions under **Settings > Appearance** to see them before typing. Configurable hotkey, panel width, and light/dark appearance.
- **Applications** — fuzzy search over `/Applications`, `/System/Applications`, `~/Applications`, and System Settings panes, ranked by frecency.
- **Clipboard history** — `Cmd+Shift+V`, or type `cb ` in the launcher. Text (with rich text), links, images, and files; searchable, pin, paste back or copy. Retention of 1/7/30 days or forever, an item limit, and excluded apps (password managers by default). Dismissing always restores the compact bar.
- **Notes** — a floating window listing notes as markdown files in `~/Library/Application Support/Photon/Notes`. Type `notes` in the launcher to open it.
- **File search** — type `/` or `f ` (or run *Search Files*) to search your home folder through Spotlight (`mdfind -onlyin $HOME`) plus filename/basename matching. File hits also appear in the main launcher, so `ember` can surface `Ember_Individual_Pitch.pdf` without typing “files”. Empty Files stays compact; search never sticks on a full-panel Searching overlay.
- **Keybinds** — window management commands (halves, thirds, maximize, center) searchable from the launcher. A Hyper key remains available when Accessibility is granted.

## Install

```sh
brew tap ryanstoffel/taps
brew install --cask ryanstoffel/taps/photon
```

Homebrew 7 and later only load casks from third-party taps that you have trusted, unless you spell out the full name as above. Run `brew trust ryanstoffel/taps` once so that `brew upgrade` and the short name `photon` work too.

Or download `Photon-<version>.zip` or `.dmg` from the [latest release](https://github.com/RyanStoffel/photon/releases) and move `Photon.app` to `/Applications`. Requires macOS 14 or later; the binary is universal (Apple silicon and Intel).

Photon is distributed from [RyanStoffel/homebrew-taps](https://github.com/RyanStoffel/homebrew-taps). Current builds are ad-hoc signed and not notarized, so macOS Gatekeeper blocks the first launch of a downloaded copy:

- macOS 14: Control-click `Photon.app` and choose **Open**.
- macOS 15 and later: open Photon once, then go to **System Settings > Privacy & Security** and click **Open Anyway**.
- Or remove the quarantine flag: `xattr -dr com.apple.quarantine /Applications/Photon.app`

Releases are listed in [CHANGELOG.md](CHANGELOG.md).

## Permissions

Photon is a menu-bar agent (`LSUIElement`). It does not appear in the Dock.

| Permission | When | Why |
| --- | --- | --- |
| none for the launcher itself | always | Global hotkeys do not require Input Monitoring. |
| Keyboard shortcuts | first launch | macOS Spotlight also defaults to `Cmd+Space`. Disable Spotlight's shortcut under **System Settings > Keyboard > Keyboard Shortcuts > Spotlight**. |
| Login Item | optional | "Launch at login" on the General settings tab. |
| Accessibility | Clipboard (optional), Keybinds | Pasting a clipboard item into the frontmost app. Required for window management. |
| Full Disk Access | optional | File search only sees what Spotlight indexes plus basename matches under the search roots. |

## Development

See [CONTRIBUTING.md](CONTRIBUTING.md) for the branching model, commit style, and PR flow.

```sh
git clone https://github.com/RyanStoffel/photon.git
cd photon
Scripts/package_app.sh
open build/Photon.app
```

The clipboard and files verification harness (required before merging those areas):

```sh
Scripts/check-harness.sh
```

Architecture: [docs/architecture.md](docs/architecture.md). Releases: [docs/releasing.md](docs/releasing.md). Harness: [docs/harness.md](docs/harness.md).

## License

[MIT](LICENSE)
