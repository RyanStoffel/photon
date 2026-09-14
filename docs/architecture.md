# Photon architecture

Photon is a Swift 6 menu-bar agent (`LSUIElement`, bundle id `com.ryanstoffel.photon`) built with SwiftPM. There is no committed Xcode project. `Scripts/package_app.sh` wraps the `Photon` executable in `Photon.app`.

Deployment target: macOS 14.

## Module layout

```
Sources/
  PhotonCore/           Fuzzy matching, frecency, Command, CommandRegistry
  Photon/               App process: hotkey, launcher panel, settings, wiring
  PhotonApps/           Application + System Settings pane provider
  PhotonClipboard/      Clipboard history: monitor, store, search, panel view
  PhotonNotes/          Floating markdown notes (see below)
  PhotonFiles/          Spotlight file search: provider, launcher file mode, Quick Look
  PhotonKeybinds/       Phase 2 stub (hotkeys + window management)
Tests/
  PhotonCoreTests/      FuzzyMatcher + FrecencyStore
  PhotonClipboardTests/ History rules (dedupe, retention), search ranking, store round trip
  PhotonNotesTests/     Title extraction, markdown spans, store, debounce, query parsing
  PhotonFilesTests/     Spotlight query strings, ranking, path truncation
```

`Package.swift` only adds the AppKit modules and the `Photon` executable when `os(macOS)` is true. `PhotonCore` compiles everywhere. `PhotonClipboard` is also declared for every platform: its AppKit files are wrapped in `#if canImport(AppKit)`, so the models, history rules, search, and store build and test on Linux while the monitor, paster, and views only compile on macOS.

| Module | Depends on | Imports AppKit? |
| --- | --- | --- |
| PhotonCore | -- | no |
| PhotonApps | PhotonCore | yes |
| PhotonClipboard | PhotonCore | partly (guarded) |
| PhotonNotes | PhotonCore | yes (AppKit panel, SwiftUI switcher) |
| PhotonFiles | PhotonCore | yes (plus QuickLookUI) |
| PhotonKeybinds | PhotonCore | reserved; stub is empty |
| Photon | all of the above | yes |

## How a provider plugs in

A provider is a `CommandProvider`:

```swift
public protocol CommandProvider: Sendable {
  var id: String { get }
  var displayName: String { get }
  func reload() async
  func commands(matching query: String) async -> [Command]
  func execute(_ command: Command) async throws
}
```

`Command` is a value type (`id`, `title`, `subtitle`, `keywords`, `providerID`). Providers own how they find and run things. The launcher only searches and dispatches.

To add a Phase 2 feature:

1. Put the implementation in that feature's module (`Sources/PhotonNotes/`, …). Do not grow `PhotonApps` or dump logic into `PhotonCore`.
2. Conform to `CommandProvider`. Use `FuzzyMatcher` and `FrecencyStore` from PhotonCore if the feature is searchable.
3. Register the provider in `Sources/Photon/AppRuntime.swift` only:

   ```swift
   registry.register(NotesProvider())
   ```

4. Bind settings for that feature to `SettingsStore` and replace the placeholder tab in `SettingsRootView`. Leave other tabs alone.

The registry is a list. Search asks every provider for `commands(matching:)`, scores titles with `FuzzyMatcher`, and boosts ids that `FrecencyStore` has seen. Enter calls `execute` on the provider that owns the selected command, then records the id in frecency.

Shared files that every feature touches today:

- `Sources/Photon/AppRuntime.swift` — one `register` line
- `Sources/Photon/Settings/SettingsStore.swift` — new `@AppStorage` keys if needed
- `Sources/Photon/Settings/SettingsRootView.swift` — swap a placeholder tab

Avoid editing `Command.swift` or `CommandRegistry.swift` unless the protocol itself is insufficient. Prefer a new file in your module.

### Launcher sessions and modes

Clipboard history is a `LauncherSession.clipboard` beside the command list: same search field, its own view model, prefix (`cb ` / `clipboard `), and keys. File search uses a generic `LauncherMode` protocol (`Sources/Photon/Launcher/LauncherMode.swift`): typed prefixes (`/`, `f `), an activation command id, and optional inline results after the primary list. While a mode is active the launcher shows a badge, renders `makeResultsView()`, and forwards leftover keys to `handle(_:)`. Escape or Backspace on an empty query leaves the session or mode; a second Escape hides the launcher. A mode reaches back through `LauncherModeHost` (focus, dismiss, activate the app for an auxiliary panel).

Register a mode next to the provider: `launcher.register(mode:)`. Clipboard still uses `attachClipboard` rather than this hook; a chore issue tracks unifying the two.

## File search (PhotonFiles)

Pipeline, all off the main thread except the final publish:

1. `SpotlightQueryBuilder` turns the typed text into a raw Spotlight query string (`kMDItemDisplayName == "*term*"cd || kMDItemFSName == ...`; every term must match; terms shorter than three characters only match word prefixes; `kMDItemTextContent` is added when "search file contents" is on).
2. `FileSearchEngine` (main actor) debounces 120 ms, cancels the in-flight query, and runs a `SpotlightQueryRunner`: one `NSMetadataQuery` with an `operationQueue`, scopes from settings (`NSMetadataQueryLocalComputerScope` or the home folder plus extra folders), sorted by last-used date. The query is stopped after the gathering phase; up to `max(500, 20 x limit)` hits are converted to plain `FileResult` values on the query's queue.
3. `FileRanker` scores name relevance (exact > prefix > word start > substring > file name > content), drops user-excluded folders, dedupes, sorts by relevance, last-used, modified, name, and caps at the configured limit. `FileIconCache` prefetches Finder icons before results are published so rows never pop.
4. `FileSearchController` publishes results and owns selection, Quick Look (`QuickLookCoordinator`, `QLPreviewPanel` data source found through the launcher panel's responder chain), and actions (`FileActions`: open, reveal, copy path). `FileSearchView` renders rows (icon, name, middle-truncated parent path, kind), the `Cmd+I` info strip, and the key hints.

`FilesProvider` contributes the *Search Files* command and, for queries of three or more characters, up to three strong name matches to the default list. It never blocks `CommandRegistry.search`: it returns what is cached for the exact query and otherwise starts a background search that asks the launcher to refresh when it finishes.

Spotlight privacy exclusions apply automatically because Spotlight never indexes them. The Files settings tab (`FilesSettingsView`, bound to `SettingsStore.files*` keys and bridged to `FileSearchSettings` by `FileSearchIntegration`) adds scope, content search, result limit, default action, inline results, extra folders, and excluded folders.

## PhotonNotes

Raycast-Notes-style floating notes. One markdown file per note in
`~/Library/Application Support/Photon/Notes/`; the first non-blank line is the title. No cloud, no accounts.

| Type | Role |
| --- | --- |
| `NotesController` (public) | Facade the app uses: show / toggle / hide, create, open, delete, preferences, `noteSummaries()` for the launcher. Owns the store, the current note, and autosave. |
| `NoteStore` | Directory-backed CRUD. Files are named after creation time (`Note 2026-09-14 at 03.12.45.md`) and never renamed, so launcher frecency stays stable. Writes are atomic; `rescan()` diffs modification date + size so external edits are picked up when the window becomes key. Delete moves to the Trash. |
| `NotesWindow` / `NotesPanel` | Non-activating `NSPanel` (titled, closable, resizable, `.unifiedCompact` toolbar, `NSVisualEffectView` background). Floats at `.floating` level when the preference is on. Frame is autosaved under `PhotonNotesWindow`. The panel handles ⌘N / ⌘P / ⌘W / ⌘F / ⌘+ / ⌘- / ⌘0 / Esc and routes copy / paste / undo itself because an agent app may have no Edit menu. |
| `MarkdownTextView` + `MarkdownTextStyler` | `NSTextView` (TextKit 1, plain text) styled from `MarkdownStyler` spans inside `NSTextStorageDelegate.didProcessEditing`. Content stays plain markdown; only attributes change. Clicking `[ ]` toggles it, Return continues lists. |
| `MarkdownStyler` (pure) | Line-based span computation: headings, bold / italic, inline code, fenced code, bullet and numbered lists, checkboxes. Paragraph-local restyle unless the document contains a fence. |
| `NoteSwitcherModel` / `NoteSwitcherView` | ⌘P popover anchored to the toolbar: fuzzy filter over titles (`FuzzyMatcher`), arrow keys, Return opens, "Create" when nothing matches. |
| `Debouncer` (pure) | Autosave coalescing (0.6 s) with an injectable scheduler for tests. Flushes on note switch, hide, resign key, and termination. |
| `NoteQuery` (pure) | Launcher grammar: `notes`, `note`, `n <text>`, `note <text>`, `notes <text>` list notes; anything else only matches the fixed "Notes" and "New Note" commands. |
| `NotesProvider` | `CommandProvider`: `notes.open`, `notes.new`, and `note:<id>` results. |

App-side wiring lives in `Sources/Photon/Notes/NotesIntegration.swift`: it maps `SettingsStore` (font size, float, open on launch, optional hotkey) onto `NotesPreferences`, registers the toggle hotkey as `HotkeyManager.HotkeyID.notes` (id 3), and exposes the provider that `AppRuntime` registers. `HotkeyManager` supports several hotkeys keyed by id; the launcher keeps id 1 and the original `register(combo:)` / `onPressed` API.

## Process shape

- `PhotonApp` is a SwiftUI `@main` app with `NSApplicationDelegateAdaptor`.
- `LSUIElement` keeps it out of the Dock. A `MenuBarExtra` is the visible affordance.
- `HotkeyManager` wraps Carbon `RegisterEventHotKey`. The default shortcut is `Cmd+Space`. First launch compares that shortcut to Spotlight (`com.apple.symbolichotkeys`, id 64) and shows guidance if they collide.
- `LauncherPanelController` owns a non-activating floating `NSPanel` (native material, centered). The panel is created at launch so the hotkey only has to order it front. Esc and losing key focus hide it. The panel has a command list, a clipboard session (`LauncherSession.clipboard`), and protocol-based feature modes (`LauncherMode`; file search today).
- `HotkeyManager` registers several Carbon hotkeys keyed by id: `1` is the launcher, `2` opens clipboard history, `3` toggles the notes window (off by default).
- Settings is a regular SwiftUI `Settings` scene: General, Clipboard, Notes, Files, and About are implemented; Keybinds is a placeholder bound to `SettingsStore`.

## Clipboard history (`PhotonClipboard`)

| Piece | Role |
| --- | --- |
| `ClipboardItem`, `ClipboardCapture`, `ClipboardSettings` | Value types. An item has a primary kind (`text`, `link`, `image`, `file`) plus optional secondary representations (RTF next to text, an image rendition next to text). |
| `ClipboardHistory` | Pure rules: newest first, duplicates collapse into one entry that moves to the top (by FNV-1a content hash), `prune` drops expired unpinned items then the oldest unpinned items over the limit. Pinned items never expire. |
| `ClipboardSearch` | Ranking for the clipboard view: every token must match title, body, file paths, source app, or kind; exact title hits outrank body hits, which outrank fuzzy hits; small recency and pinned bonuses. Empty query lists pinned first. |
| `ClipboardStore` | Actor. `index.json` (Codable `[ClipboardItem]`) plus `blobs/<uuid>.txt|.rtf|.png` under `~/Library/Application Support/Photon/Clipboard/`. Text up to 16 KB is inline; longer text and all images/RTF are blobs. No third-party dependencies. |
| `PasteboardMonitor` | Polls `NSPasteboard.general.changeCount` every 0.3 s on a utility queue. Skips `org.nspasteboard.ConcealedType` / `TransientType`, excluded frontmost apps, and Photon's own writes. |
| `ClipboardPaster` | Writes an item back (string, URL, RTF, PNG + TIFF, or file URLs) and sends `Cmd+V` via `CGEvent` when `AXIsProcessTrusted()`. |
| `ClipboardManager` | `@MainActor` façade: publishes items and storage size, applies settings, paste/copy, pin, delete, clear. |
| `ClipboardProvider` | The launcher command "Clipboard History" and the `cb ` / `clipboard ` prefix. Running it switches the panel into clipboard mode instead of closing it. |
| `ClipboardHistoryViewModel` / `ClipboardHistoryView` / `ClipboardPreviewView` | The panel's clipboard mode: list with type icon, source app icon, relative time; preview pane; footer with key hints. Return pastes (or copies, per setting), Cmd+Return copies, Cmd+P pins, Cmd+Delete deletes, Cmd+Shift+Delete clears after an inline confirmation, Esc goes back. |

`AppRuntime` creates one `ClipboardManager`, hands it to `LauncherPanelController.attachClipboard`, registers the provider, and mirrors `SettingsStore` into `ClipboardSettings` through `onClipboardChange`. The Clipboard settings tab (`ClipboardSettingsView`) binds to `SettingsStore` and reads storage size from the manager.

## CI

`.github/workflows/ci.yml` runs on pull requests and pushes to `develop` / `main`:

| Job | Runner | What |
| --- | --- | --- |
| `branch-name` | ubuntu-latest | Enforces `feature/GH-<n>-*`, `bug/GH-<n>-*`, `chore/*`, `docs/*`, `release/*` (passes for `develop`/`main` themselves). |
| `lint` | macos-latest | `swiftformat --lint` and `swiftlint lint --strict`. |
| `test` | macos-latest | `swift test` (PhotonCoreTests, PhotonClipboardTests, PhotonNotesTests, PhotonFilesTests). |
| `build` | macos-latest | `Scripts/package_app.sh`, uploads `Photon.app`. |

Those four job names are the required status checks. SwiftPM `.build` is cached per job.

`.github/workflows/release.yml` runs on `v*.*.*` tags. See [releasing.md](releasing.md).

## Local build

```sh
Scripts/package_app.sh
open build/Photon.app
```

See [CONTRIBUTING.md](../CONTRIBUTING.md).
