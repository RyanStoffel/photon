import AppKit
import PhotonNotes

/// Wires the Notes module to `SettingsStore` and `HotkeyManager`. Owned by `AppRuntime`.
@MainActor
final class NotesIntegration {
  static let hotkeyID = HotkeyManager.HotkeyID.notes

  let controller: NotesController
  let provider: NotesProvider

  private let settings: SettingsStore
  private let hotkey: HotkeyManager
  private var registeredCombo: HotkeyCombo?

  init(settings: SettingsStore, notesDirectory: URL = NoteStore.defaultDirectory(), hotkey: HotkeyManager = .shared) {
    self.settings = settings
    self.hotkey = hotkey
    controller = NotesController(directory: notesDirectory, preferences: Self.preferences(from: settings))
    provider = NotesProvider(controller: controller)
    controller.onPreferencesChange = { [weak self] preferences in
      self?.store(preferences)
    }
  }

  func start() {
    settings.onNotesChange = { [weak self] in
      self?.applySettings()
    }
    applyHotkey()
    if settings.notesOpenOnLaunch {
      controller.show(focus: false)
    }
  }

  /// UI scenario mode: wire settings without opening notes on launch.
  func startWithoutOpenOnLaunch() {
    settings.onNotesChange = { [weak self] in
      self?.applySettings()
    }
  }

  func stop() {
    settings.onNotesChange = nil
    hotkey.unregister(id: Self.hotkeyID)
    registeredCombo = nil
    controller.flush()
  }

  private func applySettings() {
    controller.preferences = Self.preferences(from: settings)
    applyHotkey()
  }

  private func applyHotkey() {
    let combo = settings.notesHotkey
    guard combo != registeredCombo else {
      return
    }
    hotkey.unregister(id: Self.hotkeyID)
    registeredCombo = nil
    guard let combo else {
      return
    }
    do {
      try hotkey.register(combo: combo, id: Self.hotkeyID) { [weak self] in
        self?.controller.toggle()
      }
      registeredCombo = combo
    } catch {
      NSLog("Photon: failed to register notes hotkey: \(error)")
    }
  }

  /// Writes editor-driven changes (⌘+ / ⌘-) back to settings without echoing them into the controller.
  private func store(_ preferences: NotesPreferences) {
    if settings.notesFontSize != preferences.fontSize {
      settings.notesFontSize = preferences.fontSize
    }
    if settings.notesFloatsAboveOtherWindows != preferences.floatsAboveOtherWindows {
      settings.notesFloatsAboveOtherWindows = preferences.floatsAboveOtherWindows
    }
  }

  private static func preferences(from settings: SettingsStore) -> NotesPreferences {
    NotesPreferences(
      fontSize: settings.notesFontSize,
      floatsAboveOtherWindows: settings.notesFloatsAboveOtherWindows
    )
  }
}
