# Changelog

All notable changes to Photon are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html). The release workflow publishes the section for the tagged version as the GitHub Release notes.

## [Unreleased]

## [0.3.9] - 2026-09-18

Ryan Notes chrome and launcher recs-scroll release.

### Changed

- Notes drop the persistent sidebar for Raycast-style chrome: vibrancy editor, centered title, traffic lights, character count, switcher overlay (⌘P), ⌘K actions (New, Duplicate, Browse, Find, Copy, Deeplink, Export, list-item move, Format), and a formatting toolbar. Width is a constant **680pt**; height can grow.
- Empty-query launcher recommendations list the full unique catalog (up to 250 apps, recs, and shortcuts) instead of wrapping at the first visible page.

### Fixed

- Down on the last on-screen recommendation scrolls the list instead of jumping to the first row. The expanded launcher stays **760 × 502**. Notes, Files, clipboard, drag, paste, and ember ranking are otherwise unchanged.

## [0.3.8] - 2026-09-17

Ryan Files footer, folder grants, panel drag, and center-snap release.

### Fixed

- Files and clipboard detail metadata stay above a reserved footer-safe inset, so Created / Modified dates no longer paint over Open, Reveal, Quick Look, or Copy Path.
- Folder grants keep the Files panel visible. Photon presents NSOpenPanel as a sheet on the launcher, queues remaining grants one at a time, persists security-scoped bookmarks, and resumes search without a relaunch. Ungranted Documents / Desktop / Downloads are no longer walked in a way that fires TCC from a disappearing panel.
- The whole launcher is draggable after a small movement slop, including the search field, list padding, preview, and footer, while clicks still select rows and activate buttons.
- Horizontal snap uses the span between the dotted edge guides. If the panel's horizontal center sits between those guides, X snaps to screen center on live drag and on release.

## [0.3.7] - 2026-09-17

Ryan shared-panel sizing and instant expansion release.

### Fixed

- The default launcher is modestly wider at 760 points, while pressing Down keeps that width unchanged and expands only vertically.
- Launcher recommendations, Files, and expanded Clipboard History now use the exact same 760 × 502-point default outer dimensions.
- Files and clipboard retain their side-by-side list/detail split inside the shared panel size.
- Launcher size changes are instant; the previous 150ms expansion animation was removed.
- Packaged macOS parity compares the launcher-recommendations, Files, and clipboard frames for exact equality and captures each expanded layout.

## [0.3.6] - 2026-09-17

Ryan layout, animation, clipboard selection, and smoke-harness release.

### Fixed

- Files mode and clipboard history expanded views split **list left, preview and metadata right** inside the compact launcher width. The panel no longer stacks preview below the list or jumps sideways.
- Launcher height animation is a snappy ~150ms ease-out dropdown for Files promotion and Clipboard History Enter.
- Clipboard Up/Down redraws the selected left-list row so the highlight tracks the preview.
- Packaged `smoke` native-parity: empty Files after an `ember` search loads recents instead of replaying the previous query; EXIT cleanup waits for child processes instead of dumping SIGTERM as the failure.

## [0.3.5] - 2026-09-17

Ryan UX and real-world file search release.

### Fixed

- Files mode and clipboard history expand downward inside the launcher width preset; the panel no longer jumps to a wider detail width.
- File search walks security-scoped grants plus readable Documents, Desktop, and Downloads under the home scope when Spotlight misses unindexed files.
- Main-bar Files promotion seeds the Files session from inline hits so results do not clear while the full search runs.
- Enter on Clipboard History from the main launcher opens the split detail view immediately.

### Added

- macOS parity gate for Ryan-like `Documents/School/Capstone/Individual Pitch/Ember_Individual_Pitch.pdf` via filesystem fallback (without relying on `mdimport` for that path).

## [0.3.4] - 2026-09-17

Regression fix release for Ryan's v0.3.3 file search, drag guides, main-bar Files layout, and clipboard Enter paste.

### Fixed

- Main-bar file queries with filename hits promote into the full Files session (recents path, split preview, metadata footer) instead of a compact inline command list.
- File search shares one Spotlight engine between inline discovery and Files mode, and empty Spotlight results no longer masquerade as missing folder access when Spotlight is still available.
- Launcher drag guides mark the centered panel's left and right edges again; horizontal snap uses a narrow center band so off-center placement is preserved on release.
- Clipboard paste hides Photon, reactivates the prior app with `NSApp.hide`, and uses a longer delivery delay so Enter paste reaches the focused field when Accessibility is trusted.
- The packaged macOS gate verifies mixed-bar Files promotion, guide span, and real paste sentinel delivery.

## [0.3.3] - 2026-09-15

Workflow completion release for clipboard paste-back, guided file access, launcher dragging, and expanded Clipboard and Files detail views.

### Added

- Clipboard history expands from the compact `Cmd+Shift+V` bar into a split list and full text, link, or image preview with source, type, count, dimensions, size, and timestamp metadata.
- Files opens to Recent Files with a persistent Quick Look thumbnail and Name, Where, Type, Size, Created, and Modified metadata; keyboard selection updates the PDF or image preview.
- Files offers a one-time, least-privilege folder selection flow and persists security-scoped bookmarks instead of probing protected folders from the launcher.

### Fixed

- Clipboard paste restores the previously focused app before posting `Cmd+V`, refreshes Accessibility trust at action time, and no longer reports missing permission when event creation fails while trust is granted.
- Launcher dragging starts from safe top and side chrome without stealing search, row, scroll, button, or footer clicks. X remains free outside a narrow center corridor, snaps inside it, and Y remains independently adjustable.
- File fallback traversal is limited to user-selected roots, so protected-folder permission dialogs no longer cascade or close Photon; successful setup resumes the pending `ember` search and survives relaunch.
- The required packaged-app macOS gate now verifies sentinel paste-back, folder grant persistence, free/snap drag frames, full clipboard text and image detail, Files recents and queried PDF/image previews, metadata OCR, and light/dark rendering.

## [0.3.2] - 2026-09-15

Runtime reliability release for real-account file search and clipboard keyboard navigation.

### Fixed

- File search now combines concurrent Spotlight queries with a bounded filename walk, so recently created or unindexed home-folder documents appear in explicit Files mode and mixed launcher results.
- Launcher key navigation is intercepted by the key `NSPanel` before SwiftUI's search field, restoring physical Up/Down behavior for clipboard history from both its global hotkey and the main launcher.
- The required packaged-app macOS gate now seeds a real Documents PDF and four pasteboard entries, asserts actual displayed rows and selection changes through Accessibility and CGEvents, and captures runtime evidence screenshots.

## [0.3.1] - 2026-09-15

Emergency rollback release: restore the v0.2.3 Swift/AppKit implementation after the v0.3.0 Rust/GPUI rewrite failed the native macOS parity gate.

### Fixed

- Restored the borderless floating `NSPanel`, accessory activation policy, and menu-bar item/menu. Photon stays out of the Dock and the launcher has no title bar or traffic lights.
- Restored live system light/dark appearance, top-edge-anchored panel resizing, Finder application bundle icons, and the global `Cmd+Shift+V` clipboard workflow.
- Restored the complete v0.2.3 feature set: app and System Settings search, calculator, home file search and mixed results, empty-Down recommendations, notes, settings, configurable hotkeys, drag/snap, keybinds, and footer actions.
- Added a packaged-app runtime harness on `macos-latest`. It drives global hotkeys, clicks, typing, arrow navigation, live appearance changes, and clipboard reopen; it inspects `NSRunningApplication`, `CGWindow`, panel style/frame, menu status, and icon resolution.
- Added light/dark screenshot validation that rejects traffic-light-like title chrome and oversized compact launcher captures.

### Changed

- The Rust/GPUI rewrite remains recorded in v0.3.0 history but is not the shipping implementation. Swift 6 + SwiftUI/AppKit is the release stack again.

## [0.3.0] - 2026-09-14

Rust + GPUI rewrite. Superseded by v0.3.1 because the shipped app regressed native macOS panel, Dock/menu, appearance, positioning, icon, clipboard, and feature behavior.

## [0.2.3] - 2026-09-14

Patch release: clipboard reopen/arrows, live-snap drag, Documents file search, and Down-to-recents.

### Fixed

- Clipboard: Down expands history and Up/Down cycle items after typing. Closing and reopening (Cmd+Shift+V or from the main search) restores the compact Photon bar; the panel size and mode reset on dismiss so the next open is not a clipped bar in a huge overlay.
- Launcher: while dragging, X live-snaps so the panel sits between the two dotted edge guides. Drag mostly vertically to set height; X leaves the corridor only when pulled clearly outside the guides.
- File search: `ember` surfaces `Ember_Individual_Pitch.pdf` and similar Documents files via Spotlight `mdfind -onlyin $HOME` plus a `mdfind -name` filename fallback. File hits mix into the main launcher without typing “files”. `mdfind` times out so Files cannot stick on Searching.
- Launcher: Down on the empty/default bar reveals recommended apps and other recents. The hairline under the search field is slightly darker on top.

## [0.2.2] - 2026-09-14

Patch release: clipboard arrow navigation, search-field mode pills removed, live launcher drag, and Spotlight `mdfind` file search.

### Fixed

- Clipboard: Down/Up (plus Home/End, Page Up/Down, Control+N/P) cycle history items. The compact bar expands on Down or typing, like the main launcher; empty history stays compact.
- Launcher: Clipboard and Files no longer show a blue capsule in the search field. The mode name stays in the footer corner.
- Launcher: dragging the search bar follows the pointer in screen space (no jitter or fighting the mouse). Vertical position is stored. The panel snaps when its midpoint sits between the edge guides.
- File search: queries Spotlight with `mdfind -onlyin $HOME` (Raycast-style), splits punctuation so `ember_individual` matches `Ember_Individual_Pitch`, and resolves `/System/Volumes/Data` firmlinks before filtering system paths. Empty Files stays compact until you type.

## [0.2.1] - 2026-09-14

Patch release: launcher polish, home-scoped file search, compact clipboard hotkey panel, and drag guide fixes.

### Fixed

- Launcher: calculator section spacing below the search hairline.
- File search: default and Files-mode Spotlight scope stay in the home folder; system paths outside `~` are filtered; legacy **This Mac** preference migrates to **Home**.
- Clipboard: `Cmd+Shift+V` opens the compact launcher bar; Down arrow expands history rows like the main launcher.
- Launcher: reposition guides align with the panel edges; drag the search bar without holding the launcher shortcut; file search starts compact until you type or press Down.

## [0.2.0] - 2026-09-14

Feature release: inline calculator and unit conversions, launcher drag-and-snap positioning, clipboard and file-search UX aligned with the redesigned launcher, and searchable System Settings pane titles.

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

### Known limitations

- The build is ad-hoc signed and not notarized. macOS blocks the first launch of a downloaded copy until you allow it (Control-click > Open on macOS 14; System Settings > Privacy & Security > Open Anyway on macOS 15 and later; or `xattr -dr com.apple.quarantine /Applications/Photon.app`).

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

[Unreleased]: https://github.com/RyanStoffel/photon/compare/v0.3.7...HEAD
[0.3.7]: https://github.com/RyanStoffel/photon/compare/v0.3.6...v0.3.7
[0.3.6]: https://github.com/RyanStoffel/photon/compare/v0.3.5...v0.3.6
[0.3.5]: https://github.com/RyanStoffel/photon/compare/v0.3.4...v0.3.5
[0.3.1]: https://github.com/RyanStoffel/photon/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/RyanStoffel/photon/releases/tag/v0.3.0
[0.2.3]: https://github.com/RyanStoffel/photon/releases/tag/v0.2.3
[0.2.2]: https://github.com/RyanStoffel/photon/releases/tag/v0.2.2
[0.2.1]: https://github.com/RyanStoffel/photon/releases/tag/v0.2.1
[0.2.0]: https://github.com/RyanStoffel/photon/releases/tag/v0.2.0
[0.1.1]: https://github.com/RyanStoffel/photon/releases/tag/v0.1.1
[0.1.0]: https://github.com/RyanStoffel/photon/releases/tag/v0.1.0
