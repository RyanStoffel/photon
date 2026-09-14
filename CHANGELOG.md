# Changelog

All notable changes to Photon are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html). The release workflow publishes the section for the tagged version as the GitHub Release notes.

## [Unreleased]

### Added

- Launcher: inline calculator and unit conversions. Type a math expression (`30/5`, `(2+3)*4`, `2^10`) or a conversion (`10 km to mi`, `32 f to c`) to see a result row; Enter copies the result to the clipboard. Local parser only, no AI.
- Launcher: hold your launcher shortcut and drag the search bar to move the panel vertically; dotted guides mark the horizontal center and the panel snaps to center when dropped between them. Position is remembered across sessions. Settings > Appearance includes **Reset launcher position to center**.

### Changed

- Launcher: calculator and unit conversion results use a Raycast-style split card (expression and result with caption pills, center arrow) instead of a list row; the footer action reads **Copy Answer**.
- Clipboard mode: matches the compact launcher layout. The panel stays search-field height until history items appear, then grows row by row. The mode is labeled in the footer instead of a pill beside the search field. Rows use the same icon, title, and secondary relative-time styling as launcher commands; pin, delete, paste, and keyboard shortcuts are unchanged.
- File search: default scope is your home folder instead of the whole Mac. Settings still offers This Mac, plus extra and excluded folders.
- File search: fuzzy matching on file names and home-relative paths (case-insensitive; spaces, underscores, and punctuation are ignored), aligned with the app launcher.
- Files mode: result rows and the empty state match the redesigned launcher (40 pt rows, icon and name with a truncated `~/…` path on the same line).

### Fixed

- Launcher: System Settings panes are indexed and shown by their human-facing titles (localized bundle names and common pane labels), with searchable aliases such as `wallpaper`, `privacy`, `bluetooth`, and `battery`, instead of internal `.prefPane` bundle filenames.

## [0.1.1] - 2026-09-14

UI polish release: redesigned launcher, Appearance settings, real app icons, Notes sidebar, and a screenshot harness for visual QA on macOS.

### Added

- Settings > Appearance: show suggestions before typing (off by default), panel width (Compact / Regular / Wide), and appearance (System / Light / Dark) for every Photon window.
- Developer: `Scripts/screenshots.sh` and CI wiring to capture launcher and settings screenshots on macOS for PR visual QA.

### Changed

- Launcher: redesigned panel. A wider (740 pt), rounded panel on the system popover material with a hairline border; a 20 pt search field with the placeholder "Search apps, files, notes and more…"; a footer with the app name and the key hint for the selected row. The panel opens as a single search field and grows as results arrive; suggestions before typing are an option.
- Launcher rows: icon and name only for applications (no path); subtitles stay where they carry meaning (System Settings, file location, command descriptions, window shortcuts) and render as secondary text on the same line. Rows are 40 pt with a rounded selection highlight; commands without an app icon get a small symbol tile.
- Notes: the window now has a collapsible sidebar (`NSSplitViewController`, system sidebar material) listing every note with its title, a one-line snippet, and a Notes-style date, newest first. `Cmd+P` focuses the list instead of opening a popover; `Ctrl+Cmd+S` hides or shows the sidebar; the sidebar's width and collapsed state are remembered. The toolbar uses the unified style with the standard sidebar toggle, "New Note" beside it, and an `ellipsis.circle` menu (Float on Top, Reveal in Finder, Delete Note). The editor styles the first line as a title, uses wider insets, and sits on the standard text background. The window title is the current note's title. Text size commands moved out of the menu; `Cmd+=` / `Cmd+-` / `Cmd+0` and the Notes settings tab still control it.

### Fixed

- Launcher: application rows show the app's real icon instead of a placeholder square. The launcher never asked the system for app icons; commands now carry an icon description that the launcher resolves and caches. System Settings panes use their own pane icon and fall back to the System Settings icon; clipboard, notes, file, and window commands have fitting icons too.
- Notes: full-height sidebar and tracking separator when the window uses `fullSizeContentView`.

### Known limitations

- The build is ad-hoc signed and not notarized. macOS blocks the first launch of a downloaded copy until you allow it (Control-click > Open on macOS 14; System Settings > Privacy & Security > Open Anyway on macOS 15 and later; or `xattr -dr com.apple.quarantine /Applications/Photon.app`).

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

[Unreleased]: https://github.com/RyanStoffel/photon/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/RyanStoffel/photon/releases/tag/v0.1.1
[0.1.0]: https://github.com/RyanStoffel/photon/releases/tag/v0.1.0
