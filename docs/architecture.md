# Photon architecture

Photon is a Rust menu-bar agent (`LSUIElement`, bundle id `com.ryanstoffel.photon`) built with Cargo and [GPUI](https://www.gpui.rs/). There is no Xcode project and no Swift app binary. `Scripts/package_app.sh` wraps the `photon` executable in `Photon.app`.

Deployment target: macOS 14.

## Crate layout

```
crates/
  photon-core/        Layout, fuzzy match, calculator, frecency, launcher session, screenshot expectations
  photon-clipboard/   History rules, search, JSON persistence (text/links/images/files)
  photon-files/       mdfind invocation, basename walk, ranking
  photon/             GPUI app (macOS): launcher, settings, notes, hotkeys, clipboard capture
```

| Crate | Depends on | GPUI / AppKit? |
| --- | --- | --- |
| photon-core | -- | no |
| photon-clipboard | photon-core | no |
| photon-files | photon-core | no (`mdfind` via `std::process`) |
| photon | all of the above | yes, `cfg(target_os = "macos")` |

Linux cannot run the GPUI shell. Unit tests for layout, clipboard keys, and file ranking run everywhere, including GitHub-hosted Macs with an empty Spotlight index (the files harness walks a fixture home).

## Launcher session

`photon_core::launcher::LauncherState` is the headless model the GPUI window drives:

- Compact content is `SearchOnly` (89 pt: 56 search + 1 hairline + 32 footer).
- Clipboard: `Cmd+Shift+V` and entering clipboard from the main list start compact. Down expands history; Up/Down cycle with or without a query. `hide()` / `reset_transient()` collapse so the next open is not a clipped bar in a huge overlay.
- Files: empty query and in-flight search stay compact. Results expand the list. There is no full-height Searching overlay.

## File search

1. `mdfind -onlyin $HOME` metadata query (and extra folders).
2. `mdfind -name <term>` filename fallback (underscore-tokenized names such as `Ember_Individual_Pitch.pdf`).
3. Basename walk of the search root, skipping heavy directories. This is what makes CI pass when Spotlight's index is empty.

`FileRanker` then scores stem / filename / relative path. Documents whose first filename token equals the query (`ember` → `Ember_Individual_Pitch`) get a 0.93 bonus so they are not buried under prefixed folders in `~/Developer`.

File hits mix into the main launcher when the query is not an app, Settings, clipboard, or calculator match, without typing “files”.

## Clipboard persistence

History is JSON under Application Support (`clipboard-index.json`), including text, links, image blobs, and file paths. Pin, prune, and excluded bundle IDs (password managers by default) match the previous Swift store rules.

## Screenshots

`PHOTON_UI_SCENARIO` / `--ui-scenario` still exist. Compact scenarios (`launcher-empty`, `clipboard-empty`, `files-empty`) must keep panel height at `LauncherLayout::compact_height()`. `Scripts/check-screenshot-compact.sh` rejects PNGs taller than 420 px for those slugs.
