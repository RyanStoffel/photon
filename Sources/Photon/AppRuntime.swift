import AppKit
import PhotonApps
import PhotonClipboard
import PhotonCore
import PhotonFiles
import PhotonKeybinds
import PhotonNotes

/// Process-wide wiring. Phase 2 features register here with a single line.
@MainActor
final class AppRuntime: ObservableObject {
  let settings: SettingsStore
  let registry = CommandRegistry()
  let launcher: LauncherPanelController
  private let hotkey = HotkeyManager.shared
  private let frecencyURL: URL

  init() {
    let settings = SettingsStore()
    self.settings = settings
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSTemporaryDirectory())
    let dir = support.appendingPathComponent("Photon", isDirectory: true)
    frecencyURL = dir.appendingPathComponent("frecency.json")
    launcher = LauncherPanelController(settings: settings, registry: registry, frecencyURL: frecencyURL)
    registerProviders()
  }

  func start() {
    launcher.preload()
    Task {
      await registry.reloadAll()
    }
    applyHotkey()
    settings.onHotkeyChange = { [weak self] in
      self?.applyHotkey()
    }
    SpotlightConflict.adviseIfNeeded(current: settings.hotkey)
  }

  func stop() {
    hotkey.unregister()
    persistFrecency()
    settings.onHotkeyChange = nil
  }

  func toggleLauncher() {
    launcher.toggle()
  }

  func openSettings() {
    NSApp.activate(ignoringOtherApps: true)
    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
  }

  /// Phase 2: add `registry.register(YourProvider())` here. Do not edit PhotonCore.
  private func registerProviders() {
    registry.register(AppsProvider())
    registry.register(ClipboardProvider())
    registry.register(NotesProvider())
    registry.register(FilesProvider())
    registry.register(KeybindsProvider())
  }

  private func applyHotkey() {
    hotkey.onPressed = { [weak self] in
      self?.toggleLauncher()
    }
    do {
      try hotkey.register(combo: settings.hotkey)
    } catch {
      NSLog("Photon: failed to register hotkey: \(error)")
    }
  }

  private func persistFrecency() {
    do {
      try launcher.currentFrecency().save(to: frecencyURL)
    } catch {
      NSLog("Photon: could not save frecency: \(error)")
    }
  }
}
