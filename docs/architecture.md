# Photon architecture

Photon is a Swift 6 menu-bar agent (`LSUIElement`, bundle id `com.ryanstoffel.photon`) built with SwiftPM. There is no committed Xcode project. `Scripts/package_app.sh` wraps the `Photon` executable in `Photon.app`.

Deployment target: macOS 14.

## Module layout

```
Sources/
  PhotonCore/           Fuzzy matching, frecency, Command, CommandRegistry
  Photon/               App process: hotkey, launcher panel, settings, wiring
  PhotonApps/           Application + System Settings pane provider
  PhotonClipboard/      Phase 2 stub
  PhotonNotes/          Phase 2 stub
  PhotonFiles/          Phase 2 stub
  PhotonKeybinds/       Phase 2 stub (hotkeys + window management)
Tests/
  PhotonCoreTests/      FuzzyMatcher + FrecencyStore
```

`Package.swift` only adds the AppKit modules and the `Photon` executable when `os(macOS)` is true. `PhotonCore` is the only target that compiles on Linux, which is why Phase 1 unit tests live there.

| Module | Depends on | Imports AppKit? |
| --- | --- | --- |
| PhotonCore | -- | no |
| PhotonApps | PhotonCore | yes |
| PhotonClipboard / Notes / Files / Keybinds | PhotonCore | reserved; stubs are empty |
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
- `LauncherPanelController` owns a non-activating floating `NSPanel` (native material, centered). The panel is created at launch so the hotkey only has to order it front. Esc and losing key focus hide it.
- Settings is a regular SwiftUI `Settings` scene: General and About are implemented; Clipboard, Notes, Files, and Keybinds are placeholders bound to `SettingsStore`.

## CI

`.github/workflows/ci.yml` runs on pull requests and pushes to `develop` / `main`:

| Job | Runner | What |
| --- | --- | --- |
| `branch-name` | ubuntu-latest | Enforces `feature/GH-<n>-*`, `bug/GH-<n>-*`, `chore/*`, `docs/*`, `release/*` (passes for `develop`/`main` themselves). |
| `lint` | macos-latest | `swiftformat --lint` and `swiftlint lint --strict`. |
| `test` | macos-latest | `swift test` (PhotonCoreTests). |
| `build` | macos-latest | `Scripts/package_app.sh`, uploads `Photon.app`. |

Those four job names are the required status checks. SwiftPM `.build` is cached per job.

`.github/workflows/release.yml` runs on `v*.*.*` tags. See [releasing.md](releasing.md).

## Local build

```sh
Scripts/package_app.sh
open build/Photon.app
```

See [CONTRIBUTING.md](../CONTRIBUTING.md).
