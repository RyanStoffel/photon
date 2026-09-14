# Photon architecture

Photon is a Swift 6 menu-bar agent (`LSUIElement`, bundle id `com.ryanstoffel.photon`) built with SwiftPM. There is no committed Xcode project. `Scripts/package_app.sh` wraps the `Photon` executable in `Photon.app`.

Deployment target: macOS 14.

## Module layout

```
Sources/
  PhotonCore/           Fuzzy matching, frecency, Command, CommandRegistry, launcher layout and row rules
  Photon/               App process: hotkey, launcher panel, settings, wiring
  PhotonApps/           Application + System Settings pane provider
  PhotonClipboard/      Clipboard history: monitor, store, search, panel view
  PhotonNotes/          Floating markdown notes (see below)
  PhotonFiles/          Spotlight/`mdfind` file search: provider, launcher file mode, Quick Look
  PhotonKeybinds/       Hyper key, app hotkeys, window management
  PhotonCalculator/     Inline launcher calculator and unit conversions
Tests/
  PhotonCoreTests/      FuzzyMatcher, FrecencyStore, Command icons, launcher layout and rows
  PhotonAppsTests/      System Settings pane icon policy
  PhotonClipboardTests/ History rules (dedupe, retention), search ranking, store round trip
  PhotonNotesTests/     Title extraction, markdown spans, store, debounce, query parsing, sidebar rows
  PhotonFilesTests/     Spotlight query strings, mdfind args, ranking, path truncation
  PhotonKeybindsTests/  Frame math, shortcut parsing, conflicts, hidutil mapping format
```

`Package.swift` only adds the AppKit modules and the `Photon` executable when `os(macOS)` is true. `PhotonCore` compiles everywhere. `PhotonClipboard` is also declared for every platform: its AppKit files are wrapped in `#if canImport(AppKit)`, so the models, history rules, search, and store build and test on Linux while the monitor, paster, and views only compile on macOS.

| Module | Depends on | Imports AppKit? |
| --- | --- | --- |
| PhotonCore | -- | no |
| PhotonApps | PhotonCore | yes |
| PhotonClipboard | PhotonCore | partly (guarded) |
| PhotonNotes | PhotonCore | yes (AppKit panel and split view, SwiftUI sidebar list) |
| PhotonFiles | PhotonCore | yes (plus QuickLookUI) |
| PhotonKeybinds | PhotonCore | yes (plus ApplicationServices, CoreGraphics, IOKit) |
| PhotonCalculator | PhotonCore | partly (pasteboard copy guarded) |
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

`Command` is a value type (`id`, `title`, `subtitle`, `keywords`, `providerID`, optional `icon`). Providers own how they find and run things. The launcher only searches and dispatches.

`icon` is a `CommandIcon`: the Finder icon of a path (`.fileIcon`), an image file (`.imageFile`), an application by bundle id (`.application`), a named image in a bundle or its asset catalog (`.bundleResource`), or an SF Symbol (`.symbol`). It stays a plain value so `PhotonCore` needs no AppKit; `Sources/Photon/Launcher/CommandIconCache.swift` resolves and caches the `NSImage`s (`NSWorkspace.icon(forFile:)`, `NSImage(contentsOfFile:)`, `urlForApplication(withBundleIdentifier:)`) and is warmed in the background once the providers have loaded. Apps use their bundle's Finder icon; System Settings panes go through `PaneIconPolicy` (`PhotonApps`), which reads the pane's declared icon (`NSPrefPaneIconFile`, `CFBundleIconFile`, or an asset catalog entry) and falls back to the System Settings app icon.

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

Clipboard history is a `LauncherSession.clipboard` beside the command list: same search field, its own view model, prefix (`cb ` / `clipboard `), and keys. File search uses a generic `LauncherMode` protocol (`Sources/Photon/Launcher/LauncherMode.swift`): typed prefixes (`/`, `f `), an activation command id, and optional inline results after the primary list. While a mode is active the launcher labels the footer corner (not the search field), renders `makeResultsView()`, and forwards leftover keys to `handle(_:)`. Escape or Backspace on an empty query leaves the session or mode; a second Escape hides the launcher. A mode reaches back through `LauncherModeHost` (focus, dismiss, activate the app for an auxiliary panel).

Register a mode next to the provider: `launcher.register(mode:)`. Clipboard still uses `attachClipboard` rather than this hook; a chore issue tracks unifying the two.

## File search (PhotonFiles)

Pipeline, all off the main thread except the final publish:

1. `SpotlightQueryBuilder` turns the typed text into a raw Spotlight query string (`kMDItemDisplayName == "*term*"cd || kMDItemFSName == ...`; every alphanumeric term must match; underscores and punctuation split terms so `ember_individual` is `ember` AND `individual`; terms shorter than three characters only match word prefixes; `kMDItemTextContent` is added when "search file contents" is on).
2. `FileSearchEngine` (main actor) debounces 120 ms, cancels the in-flight query, and runs `MdfindQueryRunner`: one `/usr/bin/mdfind -onlyin $HOME` (plus extra folders; omitted for **This Mac**) with `-0` null-terminated paths. Up to `max(500, 20 x limit)` hits become `FileResult` values via `FileResultFactory`. This is the same Spotlight/`mdfind` path Raycast uses; the engine does not walk the filesystem.
3. `FileRanker` scores name relevance (exact > prefix > word start > substring > file name > content), drops user-excluded folders and blocked system paths (`/System`, `/Library` except `~/Library`, `/private`, `/usr`, `/bin`) after resolving `/System/Volumes/Data` firmlinks, dedupes, sorts by relevance, last-used, modified, name, and caps at the configured limit. `FileIconCache` prefetches Finder icons before results are published so rows never pop.
4. `FileSearchController` publishes results and owns selection, Quick Look (`QuickLookCoordinator`, `QLPreviewPanel` data source found through the launcher panel's responder chain), and actions (`FileActions`: open, reveal, copy path). Empty Files mode stays a compact search field until the user types. `FileSearchView` renders rows (icon, name, middle-truncated parent path, kind), the `Cmd+I` info strip, and the key hints.

`FilesProvider` contributes the *Search Files* command and, for queries of three or more characters, up to three strong name matches to the default list. It never blocks `CommandRegistry.search`: it returns what is cached for the exact query and otherwise starts a background search that asks the launcher to refresh when it finishes.

Spotlight privacy exclusions apply automatically because Spotlight never indexes them. Default scope is the user home folder (`mdfind -onlyin $HOME`); **This Mac** remains available in settings. `FileRanker` re-sorts Spotlight hits with launcher-style fuzzy matching on the stem, file name, and path relative to home (separator-insensitive). Paths shown in the UI abbreviate firmlink prefixes (`/System/Volumes/Data/...`) to `~/…`. The Files settings tab (`FilesSettingsView`, bound to `SettingsStore.files*` keys and bridged to `FileSearchSettings` by `FileSearchIntegration`) adds scope, content search, result limit, default action, inline results, extra folders, and excluded folders.

## PhotonNotes

Raycast-Notes-style floating notes. One markdown file per note in
`~/Library/Application Support/Photon/Notes/`; the first non-blank line is the title. No cloud, no accounts.

| Type | Role |
| --- | --- |
| `NotesController` (public) | Facade the app uses: show / toggle / hide, create, open, delete, preferences, `noteSummaries()` for the launcher. Owns the store, the current note, and autosave. |
| `NoteStore` | Directory-backed CRUD. Files are named after creation time (`Note 2026-09-14 at 03.12.45.md`) and never renamed, so launcher frecency stays stable. Writes are atomic; `rescan()` diffs modification date + size so external edits are picked up when the window becomes key. Delete moves to the Trash. |
| `NotesWindow` / `NotesPanel` | Non-activating `NSPanel` (titled, closable, resizable, `.unified` toolbar) whose `contentViewController` is an `NSSplitViewController`: a sidebar item (`NSSplitViewItem(sidebarWithViewController:)`, system sidebar material, full-height layout, 180–340 pt) hosting the SwiftUI list, and the editor column on `textBackgroundColor`. Floats at `.floating` level when the preference is on. Frame is autosaved under `PhotonNotesWindow.sidebar`; sidebar width and collapsed state are stored in `PhotonNotesSidebarWidth` / `PhotonNotesSidebarCollapsed` (`NotesWindow+Sidebar.swift`). The panel handles ⌘N / ⌘P (list ⇄ editor) / ⌃⌘S (toggle sidebar) / ⌘W / ⌘F / ⌘+ / ⌘- / ⌘0 / Esc and Return (list → editor), and routes copy / paste / undo itself because an agent app may have no Edit menu. The window title is the current note's title. |
| `NotesWindow+Toolbar` | Standard toolbar items only: `.toggleSidebar`, "New Note" (`square.and.pencil`) in the sidebar's toolbar area, `.sidebarTrackingSeparator`, flexible space, and an `NSMenuToolbarItem` (`ellipsis.circle`) with Float on Top, Reveal in Finder, Delete Note. SF Symbols at the default toolbar size, no tinting. |
| `MarkdownTextView` + `MarkdownTextStyler` | `NSTextView` (TextKit 1, plain text) styled from `MarkdownStyler` spans inside `NSTextStorageDelegate.didProcessEditing` (`NotesWindow+Editor.swift`). Content stays plain markdown; only attributes change. The first non-blank line gets the `.title` look (1.7× the body size, bold, extra paragraph spacing) layered over its markdown spans. 18 pt container insets. Clicking `[ ]` toggles it, Return continues lists. |
| `MarkdownStyler` (pure) | Line-based span computation: headings, bold / italic, inline code, fenced code, bullet and numbered lists, checkboxes. `titleSpan(in:)` marks the first non-blank line; `editAffectsTitle(_:in:)` tells the editor when an edit near the top needs a full pass. Otherwise restyling is paragraph-local unless the document contains a fence. |
| `NoteSidebarRow` (pure) / `NoteSidebarModel` / `NoteSidebarView` | Sidebar rows (title, snippet or "No additional text", Notes-style date: time today, "Yesterday", weekday within a week, else numeric) sorted newest first; the model bridges the SwiftUI `List(selection:)` to the controller and distinguishes user selection from programmatic updates. |
| `Debouncer` (pure) | Autosave coalescing (0.6 s) with an injectable scheduler for tests. Flushes on note switch, hide, resign key, and termination. |
| `NoteQuery` (pure) | Launcher grammar: `notes`, `note`, `n <text>`, `note <text>`, `notes <text>` list notes; anything else only matches the fixed "Notes" and "New Note" commands. |
| `NotesProvider` | `CommandProvider`: `notes.open`, `notes.new`, and `note:<id>` results. |

App-side wiring lives in `Sources/Photon/Notes/NotesIntegration.swift`: it maps `SettingsStore` (font size, float, open on launch, optional hotkey) onto `NotesPreferences`, registers the toggle hotkey as `HotkeyManager.HotkeyID.notes` (id 3), and exposes the provider that `AppRuntime` registers. `HotkeyManager` supports several hotkeys keyed by id; the launcher keeps id 1 and the original `register(combo:)` / `onPressed` API.

## Process shape

- `PhotonApp` is a SwiftUI `@main` app with `NSApplicationDelegateAdaptor`.
- `LSUIElement` keeps it out of the Dock. A `MenuBarExtra` is the visible affordance.
- `HotkeyManager` wraps Carbon `RegisterEventHotKey`. The default shortcut is `Cmd+Space`. First launch compares that shortcut to Spotlight (`com.apple.symbolichotkeys`, id 64) and shows guidance if they collide.
- `LauncherPanelController` owns a non-activating floating `NSPanel`. Its content view is an `NSVisualEffectView` (`.popover`, `.behindWindow`, always active) clipped to a 12 pt continuous corner radius, with the SwiftUI `LauncherView` on top. The panel is created at launch so the hotkey only has to order it front. Esc and losing key focus hide it. The panel has a command list, a clipboard session (`LauncherSession.clipboard`), and protocol-based feature modes (`LauncherMode`; file search today).
- Panel size: `LauncherLayout` (PhotonCore) is the single source of the metrics (56 pt search field, 40 pt rows, at most 8 visible, 32 pt footer, width presets 620 / 740 / 860). `LauncherViewModel` publishes a `LauncherContent` (`.searchOnly` for an empty query in compact mode, `.rows(n)` for the command list and clipboard history, or `.fullHeight` for expanded file search and other `LauncherMode` views); the controller resizes the window from it with the top edge fixed, and `LauncherView` sizes itself from the same value, so the two never disagree. Drag the search bar chrome to reposition the panel (no modifier keys); dotted snap guides sit on the panel's left and right edges when it is centred, and vertical placement persists. `LauncherRow` maps a `Command` to what a row shows (title, optional secondary detail, icon). Settings > Appearance (`launcherShowsSuggestions`, `launcherPanelWidth`, `appearance`) reach the launcher as a `LauncherPreferences` value; `appearance` is applied to `NSApp.appearance`.
- `HotkeyManager` registers several Carbon hotkeys keyed by id: `1` is the launcher, `2` opens clipboard history, `3` toggles the notes window (off by default), and `add(combo:handler:)` hands out ids from `1000` for features with a dynamic number of shortcuts (app hotkeys, window commands).
- Settings is a regular SwiftUI `Settings` scene: General, Appearance, Clipboard, Notes, Files, Keybinds, and About are all implemented and bound to `SettingsStore`.

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
| `ClipboardHistoryViewModel` / `ClipboardLauncherRow` / `ClipboardLauncherFooter` | Clipboard mode in the launcher: compact panel sizing, launcher-style rows (type icon, snippet, relative time), footer mode label and key hints. Return pastes (or copies, per setting), Cmd+Return copies, Cmd+P pins, Cmd+Delete deletes, Cmd+Shift+Delete clears after an inline confirmation, Esc goes back. |

`AppRuntime` creates one `ClipboardManager`, hands it to `LauncherPanelController.attachClipboard`, registers the provider, and mirrors `SettingsStore` into `ClipboardSettings` through `onClipboardChange`. The Clipboard settings tab (`ClipboardSettingsView`) binds to `SettingsStore` and reads storage size from the manager.

## PhotonKeybinds

`KeybindsController` (`@MainActor`, an `ObservableObject` the Keybinds tab observes) owns everything and is driven by one value, `KeybindsConfiguration`, which `SettingsStore` persists as JSON (`keybindsConfiguration`). `apply(_:)` is idempotent and runs after every settings change.

| Piece | Role |
| --- | --- |
| `KeyShortcut` / `KeyModifiers` | Key code + modifiers. `⌃⌥⇧⌘` together is the Hyper key (`isHyper`, shown as `✦`). Parses `hyper+left`, `cmd+shift+k`, `⌃⌥⇧⌘Return`; converts to Carbon and `CGEventFlags` masks. Pure. |
| `WindowAction` / `WindowLayout` | The 19 window commands and their frame math (grid cells, translate between displays, fit, screen lookup, coordinate flip). Pure, bottom-left coordinates. |
| `KeybindsConfiguration` | Hyper key settings, app hotkeys, window bindings, conflict detection. Pure. |
| `HIDKeyMapping` / `HIDKeyRemapper` | The `hidutil` `UserKeyMapping` format (pure parser and JSON argument) and the process that runs `/usr/bin/hidutil` to map the chosen key to F18 and back. Photon only ever removes its own entries. |
| `HyperKeyEngine` | Session `CGEventTap` on the main run loop. Swallows F18, adds the four modifier flags to keys typed while it is held, dispatches keys that have a Hyper shortcut, and runs the tap behaviour (nothing / Escape / Caps Lock via `IOHIDSetModifierLockState`) on a quick press. Re-enables itself when macOS disables the tap. |
| `WindowManager` | Accessibility API: frontmost app's focused window, `kAXPosition`/`kAXSize` (set size, position, size again; `AXEnhancedUserInterface` off while moving), multi-display via `NSScreen.visibleFrame`, per-window restore history. |
| `AppActivator` | App hotkey behaviour: hide when frontmost, otherwise launch or focus through `NSWorkspace`. |
| `AccessibilityPermission` | `AXIsProcessTrusted(WithOptions)`, `CGPreflightListenEventAccess`, System Settings deep links. |
| `KeybindsProvider` | Puts the window commands in the launcher (`window:<action>` ids). |

Shortcut routing: plain combinations go through the app's `HotkeyManager` (Carbon) via the `GlobalHotkeyRegistrar` protocol the app implements; Hyper combinations fire from the event tap while the Hyper key is held and are also registered with Carbon so pressing the four modifiers by hand works. While a recorder is active the controller pauses dispatch so bound shortcuts can be re-recorded.

Safety: the HID remap is only installed after the event tap exists, is removed on quit, disable, permission loss, or failure, is cleaned up on the next launch after a crash, and is never persistent (macOS drops it at logout). Nothing in the module prompts for Accessibility except a one-time first-run alert and explicit user actions on the Keybinds tab.

## CI

`.github/workflows/ci.yml` runs on pull requests and pushes to `develop` / `main`:

| Job | Runner | What |
| --- | --- | --- |
| `branch-name` | ubuntu-latest | Enforces `feature/GH-<n>-*`, `bug/GH-<n>-*`, `chore/*`, `docs/*`, `release/*` (passes for `develop`/`main` themselves). |
| `lint` | macos-latest | `swiftformat --lint` and `swiftlint lint --strict`. |
| `test` | macos-latest | `swift test` (PhotonCoreTests, PhotonAppsTests, PhotonClipboardTests, PhotonNotesTests, PhotonFilesTests, PhotonKeybindsTests). |
| `build` | macos-latest | `Scripts/package_app.sh`, uploads `Photon.app` (as a `ditto` zip so permissions and the signature survive). |
| `smoke` | macos-latest | Downloads that zip and runs `Scripts/smoke-test.sh`: `open` the app, wait 8 s, fail on exit, crash report, or fatal log. |

`branch-name`, `lint`, `build`, `test`, and `smoke` are the required status checks. SwiftPM `.build` is cached per job.

`.github/workflows/release.yml` runs on `v*.*.*` tags and, as a dry run, on `workflow_dispatch`. See [releasing.md](releasing.md).

## Local build

```sh
Scripts/package_app.sh
open build/Photon.app
```

See [CONTRIBUTING.md](../CONTRIBUTING.md).
