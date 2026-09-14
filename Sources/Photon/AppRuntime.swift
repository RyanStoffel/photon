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
  let clipboard: ClipboardManager
  let notes: NotesIntegration
  let keybinds: KeybindsController
  private let hotkey = HotkeyManager.shared
  private let frecencyURL: URL
  private var fileSearch: FileSearchIntegration?

  init() {
    let settings = SettingsStore()
    self.settings = settings
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSTemporaryDirectory())
    let dir = support.appendingPathComponent("Photon", isDirectory: true)
    frecencyURL = dir.appendingPathComponent("frecency.json")
    launcher = LauncherPanelController(settings: settings, registry: registry, frecencyURL: frecencyURL)
    clipboard = ClipboardManager(
      settings: settings.clipboardSettings,
      directory: dir.appendingPathComponent("Clipboard", isDirectory: true)
    )
    launcher.attachClipboard(clipboard)
    notes = NotesIntegration(settings: settings)
    keybinds = KeybindsController(hotkeys: hotkey)
    registerProviders()
  }

  func start() {
    launcher.preload()
    clipboard.start()
    Task {
      await registry.reloadAll()
    }
    applyHotkey()
    applyClipboardHotkey()
    settings.onHotkeyChange = { [weak self] in
      self?.applyHotkey()
    }
    settings.onClipboardChange = { [weak self] in
      self?.applyClipboardSettings()
    }
    notes.start()
    keybinds.apply(settings.keybinds)
    settings.onKeybindsChange = { [weak self] in
      guard let self else {
        return
      }
      keybinds.apply(settings.keybinds)
    }
    SpotlightConflict.adviseIfNeeded(current: settings.hotkey)
    keybinds.adviseAccessibilityIfNeeded()
  }

  func stop() {
    keybinds.stop()
    notes.stop()
    hotkey.unregisterAll()
    clipboard.stop()
    persistFrecency()
    settings.onHotkeyChange = nil
    settings.onClipboardChange = nil
    settings.onKeybindsChange = nil
  }

  func toggleLauncher() {
    launcher.toggle()
  }

  func showClipboardHistory() {
    launcher.showClipboard()
  }

  func toggleNotes() {
    notes.controller.toggle()
  }

  func openSettings() {
    NSApp.activate(ignoringOtherApps: true)
    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
  }

  /// Phase 2: add `registry.register(YourProvider())` here. Do not edit PhotonCore.
  private func registerProviders() {
    registry.register(AppsProvider())
    let clipboardProvider = ClipboardProvider()
    clipboardProvider.openHistory = { [weak self] in
      Task { @MainActor [weak self] in
        self?.showClipboardHistory()
      }
    }
    registry.register(clipboardProvider)
    registry.register(notes.provider)
    fileSearch = FileSearchIntegration(settings: settings, registry: registry, launcher: launcher)
    registry.register(KeybindsProvider(controller: keybinds))
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

  private func applyClipboardSettings() {
    clipboard.settings = settings.clipboardSettings
    applyClipboardHotkey()
  }

  private func applyClipboardHotkey() {
    guard settings.clipboardEnabled, settings.clipboardHotkeyEnabled else {
      hotkey.unregister(id: HotkeyManager.HotkeyID.clipboard)
      return
    }
    do {
      try hotkey.register(combo: settings.clipboardHotkey, id: HotkeyManager.HotkeyID.clipboard) { [weak self] in
        self?.showClipboardHistory()
      }
    } catch {
      NSLog("Photon: failed to register clipboard hotkey: \(error)")
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
