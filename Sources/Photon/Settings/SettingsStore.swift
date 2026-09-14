import Carbon
import Foundation
import PhotonClipboard

@MainActor
final class SettingsStore: ObservableObject {
  var onHotkeyChange: (() -> Void)?
  var onClipboardChange: (() -> Void)?

  private enum Keys {
    static let hotkeyKeyCode = "hotkeyKeyCode"
    static let hotkeyModifiers = "hotkeyModifiers"
    static let launchAtLogin = "launchAtLogin"
    static let clipboardEnabled = "clipboardEnabled"
    static let clipboardRetentionDays = "clipboardRetentionDays"
    static let clipboardMaxItems = "clipboardMaxItems"
    static let clipboardExcludedBundleIDs = "clipboardExcludedBundleIDs"
    static let clipboardPasteBehavior = "clipboardPasteBehavior"
    static let clipboardHotkeyEnabled = "clipboardHotkeyEnabled"
    static let clipboardHotkeyKeyCode = "clipboardHotkeyKeyCode"
    static let clipboardHotkeyModifiers = "clipboardHotkeyModifiers"
    static let notesFolderBookmark = "notesFolderBookmark"
    static let filesSearchScope = "filesSearchScope"
    static let hyperKeyEnabled = "hyperKeyEnabled"
  }

  private let defaults: UserDefaults

  @Published var hotkey: HotkeyCombo {
    didSet {
      defaults.set(Int(hotkey.keyCode), forKey: Keys.hotkeyKeyCode)
      defaults.set(Int(hotkey.carbonModifiers), forKey: Keys.hotkeyModifiers)
      onHotkeyChange?()
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

  // MARK: Clipboard

  @Published var clipboardEnabled: Bool {
    didSet {
      defaults.set(clipboardEnabled, forKey: Keys.clipboardEnabled)
      onClipboardChange?()
    }
  }

  @Published var clipboardRetention: ClipboardRetention {
    didSet {
      defaults.set(clipboardRetention.rawValue, forKey: Keys.clipboardRetentionDays)
      onClipboardChange?()
    }
  }

  @Published var clipboardMaxItems: Int {
    didSet {
      defaults.set(clipboardMaxItems, forKey: Keys.clipboardMaxItems)
      onClipboardChange?()
    }
  }

  @Published var clipboardExcludedBundleIDs: [String] {
    didSet {
      defaults.set(clipboardExcludedBundleIDs, forKey: Keys.clipboardExcludedBundleIDs)
      onClipboardChange?()
    }
  }

  @Published var clipboardPasteBehavior: ClipboardPasteBehavior {
    didSet {
      defaults.set(clipboardPasteBehavior.rawValue, forKey: Keys.clipboardPasteBehavior)
      onClipboardChange?()
    }
  }

  @Published var clipboardHotkeyEnabled: Bool {
    didSet {
      defaults.set(clipboardHotkeyEnabled, forKey: Keys.clipboardHotkeyEnabled)
      onClipboardChange?()
    }
  }

  @Published var clipboardHotkey: HotkeyCombo {
    didSet {
      defaults.set(Int(clipboardHotkey.keyCode), forKey: Keys.clipboardHotkeyKeyCode)
      defaults.set(Int(clipboardHotkey.carbonModifiers), forKey: Keys.clipboardHotkeyModifiers)
      onClipboardChange?()
    }
  }

  /// Snapshot handed to `ClipboardManager`.
  var clipboardSettings: ClipboardSettings {
    ClipboardSettings(
      isEnabled: clipboardEnabled,
      retention: clipboardRetention,
      maxItems: clipboardMaxItems,
      excludedBundleIDs: clipboardExcludedBundleIDs,
      pasteBehavior: clipboardPasteBehavior
    )
  }

  // MARK: Other features

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
    hotkey = Self.loadCombo(
      defaults,
      keyCodeKey: Keys.hotkeyKeyCode,
      modifiersKey: Keys.hotkeyModifiers,
      fallback: .defaultCombo
    )
    launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)

    clipboardEnabled = defaults.object(forKey: Keys.clipboardEnabled) as? Bool ?? true
    clipboardRetention = ClipboardRetention(
      days: defaults.object(forKey: Keys.clipboardRetentionDays) as? Int ?? ClipboardRetention.thirtyDays.rawValue
    )
    let storedMax = defaults.object(forKey: Keys.clipboardMaxItems) as? Int ?? ClipboardSettings.defaultMaxItems
    let maxRange = ClipboardSettings.maxItemsRange
    clipboardMaxItems = min(max(storedMax, maxRange.lowerBound), maxRange.upperBound)
    clipboardExcludedBundleIDs = defaults.stringArray(forKey: Keys.clipboardExcludedBundleIDs)
      ?? ClipboardSettings.defaultExcludedBundleIDs
    clipboardPasteBehavior = ClipboardPasteBehavior(
      rawValue: defaults.string(forKey: Keys.clipboardPasteBehavior) ?? ""
    ) ?? .paste
    clipboardHotkeyEnabled = defaults.object(forKey: Keys.clipboardHotkeyEnabled) as? Bool ?? true
    clipboardHotkey = Self.loadCombo(
      defaults,
      keyCodeKey: Keys.clipboardHotkeyKeyCode,
      modifiersKey: Keys.clipboardHotkeyModifiers,
      fallback: .clipboardDefaultCombo
    )

    notesFolderBookmark = defaults.string(forKey: Keys.notesFolderBookmark) ?? ""
    filesSearchScope = defaults.string(forKey: Keys.filesSearchScope) ?? "home"
    hyperKeyEnabled = defaults.object(forKey: Keys.hyperKeyEnabled) as? Bool ?? true
  }

  private static func loadCombo(
    _ defaults: UserDefaults,
    keyCodeKey: String,
    modifiersKey: String,
    fallback: HotkeyCombo
  ) -> HotkeyCombo {
    guard let code = defaults.object(forKey: keyCodeKey) as? Int,
          let mods = defaults.object(forKey: modifiersKey) as? Int
    else {
      return fallback
    }
    return HotkeyCombo(keyCode: UInt32(code), carbonModifiers: UInt32(mods))
  }
}

extension HotkeyCombo {
  /// Cmd+Shift+V opens clipboard history directly.
  static let clipboardDefaultCombo = HotkeyCombo(
    keyCode: UInt32(kVK_ANSI_V),
    carbonModifiers: UInt32(cmdKey | shiftKey)
  )
}
