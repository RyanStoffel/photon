import Foundation

@MainActor
final class SettingsStore: ObservableObject {
  static let didChangeHotkey = Notification.Name("PhotonSettingsDidChangeHotkey")

  private enum Keys {
    static let hotkeyKeyCode = "hotkeyKeyCode"
    static let hotkeyModifiers = "hotkeyModifiers"
    static let launchAtLogin = "launchAtLogin"
    static let clipboardRetentionDays = "clipboardRetentionDays"
    static let clipboardExcludeApps = "clipboardExcludeApps"
    static let notesFolderBookmark = "notesFolderBookmark"
    static let filesSearchScope = "filesSearchScope"
    static let hyperKeyEnabled = "hyperKeyEnabled"
  }

  private let defaults: UserDefaults

  @Published var hotkey: HotkeyCombo {
    didSet {
      defaults.set(Int(hotkey.keyCode), forKey: Keys.hotkeyKeyCode)
      defaults.set(Int(hotkey.carbonModifiers), forKey: Keys.hotkeyModifiers)
      NotificationCenter.default.post(name: Self.didChangeHotkey, object: self)
    }
  }

  @Published var launchAtLogin: Bool {
    didSet {
      defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
      do {
        try LoginItemManager.setEnabled(launchAtLogin)
      } catch {
        launchAtLoginError = error.localizedDescription
      }
    }
  }

  @Published var launchAtLoginError: String?

  @Published var clipboardRetentionDays: Int {
    didSet { defaults.set(clipboardRetentionDays, forKey: Keys.clipboardRetentionDays) }
  }

  @Published var clipboardExcludeApps: String {
    didSet { defaults.set(clipboardExcludeApps, forKey: Keys.clipboardExcludeApps) }
  }

  @Published var notesFolderBookmark: String {
    didSet { defaults.set(notesFolderBookmark, forKey: Keys.notesFolderBookmark) }
  }

  @Published var filesSearchScope: String {
    didSet { defaults.set(filesSearchScope, forKey: Keys.filesSearchScope) }
  }

  @Published var hyperKeyEnabled: Bool {
    didSet { defaults.set(hyperKeyEnabled, forKey: Keys.hyperKeyEnabled) }
  }

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    let storedCode = defaults.object(forKey: Keys.hotkeyKeyCode) as? Int
    let storedMods = defaults.object(forKey: Keys.hotkeyModifiers) as? Int
    if let storedCode, let storedMods {
      hotkey = HotkeyCombo(keyCode: UInt32(storedCode), carbonModifiers: UInt32(storedMods))
    } else {
      hotkey = .defaultCombo
    }
    launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
    clipboardRetentionDays = defaults.object(forKey: Keys.clipboardRetentionDays) as? Int ?? 30
    clipboardExcludeApps = defaults.string(forKey: Keys.clipboardExcludeApps) ?? "1Password, Bitwarden, LastPass"
    notesFolderBookmark = defaults.string(forKey: Keys.notesFolderBookmark) ?? ""
    filesSearchScope = defaults.string(forKey: Keys.filesSearchScope) ?? "home"
    hyperKeyEnabled = defaults.object(forKey: Keys.hyperKeyEnabled) as? Bool ?? true
  }
}
