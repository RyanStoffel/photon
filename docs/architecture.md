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
  PhotonNotes/          Phase 2 stub
  PhotonFiles/          Phase 2 stub
  PhotonKeybinds/       Phase 2 stub (hotkeys + window management)
Tests/
  PhotonCoreTests/      FuzzyMatcher + FrecencyStore
  PhotonClipboardTests/ History rules (dedupe, retention), search ranking, store round trip
```

`Package.swift` only adds the AppKit modules and the `Photon` executable when `os(macOS)` is true. `PhotonCore` compiles everywhere. `PhotonClipboard` is also declared for every platform: its AppKit files are wrapped in `#if canImport(AppKit)`, so the models, history rules, search, and store build and test on Linux while the monitor, paster, and views only compile on macOS.

| Module | Depends on | Imports AppKit? |
| --- | --- | --- |
| PhotonCore | -- | no |
| PhotonApps | PhotonCore | yes |
| PhotonClipboard | PhotonCore | partly (guarded) |
| PhotonNotes / Files / Keybinds | PhotonCore | reserved; stubs are empty |
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

## Process shape

- `PhotonApp` is a SwiftUI `@main` app with `NSApplicationDelegateAdaptor`.
- `LSUIElement` keeps it out of the Dock. A `MenuBarExtra` is the visible affordance.
- `HotkeyManager` wraps Carbon `RegisterEventHotKey`. The default shortcut is `Cmd+Space`. First launch compares that shortcut to Spotlight (`com.apple.symbolichotkeys`, id 64) and shows guidance if they collide.
- `LauncherPanelController` owns a non-activating floating `NSPanel` (native material, centered). The panel is created at launch so the hotkey only has to order it front. Esc and losing key focus hide it. The panel has two modes (`LauncherMode`): the command list, and clipboard history, which reuses the same search field.
- `HotkeyManager` registers several Carbon hotkeys keyed by id: `1` is the launcher, `2` opens clipboard history.
- Settings is a regular SwiftUI `Settings` scene: General, Clipboard, and About are implemented; Notes, Files, and Keybinds are placeholders bound to `SettingsStore`.

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
| `test` | macos-latest | `swift test` (PhotonCoreTests, PhotonClipboardTests). |
| `build` | macos-latest | `Scripts/package_app.sh`, uploads `Photon.app`. |

Those four job names are the required status checks. SwiftPM `.build` is cached per job.

`.github/workflows/release.yml` runs on `v*.*.*` tags. See [releasing.md](releasing.md).

## Local build

```sh
Scripts/package_app.sh
open build/Photon.app
```

See [CONTRIBUTING.md](../CONTRIBUTING.md).
