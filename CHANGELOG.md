# Changelog

All notable changes to Photon are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html). The release workflow publishes the section for the tagged version as the GitHub Release notes.

## [Unreleased]

### Changed

- Notes: the window now has a collapsible sidebar (`NSSplitViewController`, system sidebar material) listing every note with its title, a one-line snippet, and a Notes-style date, newest first. `Cmd+P` focuses the list instead of opening a popover; `Ctrl+Cmd+S` hides or shows the sidebar; the sidebar's width and collapsed state are remembered. The toolbar uses the unified style with the standard sidebar toggle, "New Note" beside it, and an `ellipsis.circle` menu (Float on Top, Reveal in Finder, Delete Note). The editor styles the first line as a title, uses wider insets, and sits on the standard text background. The window title is the current note's title. Text size commands moved out of the menu; `Cmd+=` / `Cmd+-` / `Cmd+0` and the Notes settings tab still control it.

### Fixed

- Launcher: application rows show the app's real icon instead of a placeholder square. The launcher never asked the system for app icons; commands now carry an icon description that the launcher resolves and caches. System Settings panes use their own pane icon and fall back to the System Settings icon; clipboard, notes, file, and window commands have fitting icons too.

## [0.1.0] - 2026-09-14

First public build. Photon is a menu-bar launcher for macOS 14 and later; it has no Dock icon, no account, no cloud sync, and no telemetry.

### Added

- Launcher: `Cmd+Space` opens a floating, non-activating search panel. The hotkey is configurable, and Photon points out the Spotlight shortcut conflict on first launch.
- Applications: fuzzy search over `/Applications`, `/System/Applications`, `~/Applications`, and System Settings panes, ranked by frecency.
- Clipboard history: `Cmd+Shift+V` or `cb ` in the launcher. Text (with rich text), links, images, and files; search, pin, paste back or copy; retention and item limits; excluded apps (password managers by default).
- Notes: a floating window with live markdown styling, one `.md` file per note under `~/Library/Application Support/Photon/Notes`, autosave, a `Cmd+P` switcher, and launcher access through `notes` and `n <title>`.
- File search: `/` or `f ` searches the whole Mac through Spotlight. Enter opens, `Cmd+Enter` reveals in Finder, Space or `Cmd+Y` toggles Quick Look, `Cmd+C` copies the path, `Cmd+I` shows details. Strong matches also appear below applications.
- Keybinds: a Hyper key (Caps Lock held becomes `Ctrl+Opt+Shift+Cmd`), user-defined shortcuts that launch, focus, or hide an app, and window management (halves, quarters, thirds, two-thirds, maximize, almost maximize, center, next or previous display, restore).
- Settings window with General, Clipboard, Notes, Files, Keybinds, and About tabs; optional launch at login.
- Distribution: universal (`arm64` + `x86_64`) `Photon-<version>.zip` and `.dmg` with `SHA256SUMS` on the GitHub Release, and the Homebrew cask `ryanstoffel/taps/photon`.

### Known limitations

- The build is ad-hoc signed and not notarized. macOS blocks the first launch of a downloaded copy until you allow it (Control-click > Open on macOS 14; System Settings > Privacy & Security > Open Anyway on macOS 15 and later; or `xattr -dr com.apple.quarantine /Applications/Photon.app`).
- Nobody has run this build on real hardware. The only runtime check is the CI smoke test, which launches the app on a GitHub-hosted Apple silicon runner for eight seconds and checks for crashes. Hotkeys, panels, clipboard capture, and window management are untested outside unit tests.
- The Intel slice of the universal binary has only been compiled, not run.
- The Hyper key and window management need Accessibility access. The Caps Lock remap uses a per-login-session `hidutil` mapping; Settings > Keybinds > Reset Key Mapping restores the key if Photon quits abnormally.

[Unreleased]: https://github.com/RyanStoffel/photon/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/RyanStoffel/photon/releases/tag/v0.1.0
