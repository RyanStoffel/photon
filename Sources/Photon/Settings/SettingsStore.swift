import Carbon
import Foundation
import PhotonClipboard

@MainActor
final class SettingsStore: ObservableObject {
  var onHotkeyChange: (() -> Void)?
  var onClipboardChange: (() -> Void)?
  var onNotesChange: (() -> Void)?

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
    static let notesFontSize = "notesFontSize"
    static let notesFloatsAboveOtherWindows = "notesFloatsAboveOtherWindows"
    static let notesOpenOnLaunch = "notesOpenOnLaunch"
    static let notesHotkeyKeyCode = "notesHotkeyKeyCode"
    static let notesHotkeyModifiers = "notesHotkeyModifiers"
    static let filesSearchScope = "filesSearchScope"
    static let filesSearchContents = "filesSearchContents"
    static let filesMaxResults = "filesMaxResults"
    static let filesDefaultAction = "filesDefaultAction"
    static let filesInlineResults = "filesInlineResults"
    static let filesExtraFolders = "filesExtraFolders"
    static let filesExcludedFolders = "filesExcludedFolders"
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

  // MARK: Notes

  @Published var notesFontSize: Double {
    didSet {
      defaults.set(notesFontSize, forKey: Keys.notesFontSize)
      onNotesChange?()
    }
  }

  @Published var notesFloatsAboveOtherWindows: Bool {
    didSet {
      defaults.set(notesFloatsAboveOtherWindows, forKey: Keys.notesFloatsAboveOtherWindows)
      onNotesChange?()
    }
  }

  @Published var notesOpenOnLaunch: Bool {
    didSet { defaults.set(notesOpenOnLaunch, forKey: Keys.notesOpenOnLaunch) }
  }

  /// Optional shortcut that toggles the notes window. `nil` means none.
  @Published var notesHotkey: HotkeyCombo? {
    didSet {
      if let notesHotkey {
        defaults.set(Int(notesHotkey.keyCode), forKey: Keys.notesHotkeyKeyCode)
        defaults.set(Int(notesHotkey.carbonModifiers), forKey: Keys.notesHotkeyModifiers)
      } else {
        defaults.removeObject(forKey: Keys.notesHotkeyKeyCode)
        defaults.removeObject(forKey: Keys.notesHotkeyModifiers)
      }
      onNotesChange?()
    }
  }

  // MARK: Other features

  @Published var filesSearchScope: String {
    didSet { defaults.set(filesSearchScope, forKey: Keys.filesSearchScope) }
  }

  @Published var filesSearchContents: Bool {
    didSet { defaults.set(filesSearchContents, forKey: Keys.filesSearchContents) }
  }

  @Published var filesMaxResults: Int {
    didSet { defaults.set(filesMaxResults, forKey: Keys.filesMaxResults) }
  }

  @Published var filesDefaultAction: String {
    didSet { defaults.set(filesDefaultAction, forKey: Keys.filesDefaultAction) }
  }

  @Published var filesInlineResults: Bool {
    didSet { defaults.set(filesInlineResults, forKey: Keys.filesInlineResults) }
  }

  @Published var filesExtraFolders: [String] {
    didSet { defaults.set(filesExtraFolders, forKey: Keys.filesExtraFolders) }
  }

  @Published var filesExcludedFolders: [String] {
    didSet { defaults.set(filesExcludedFolders, forKey: Keys.filesExcludedFolders) }
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

    notesFontSize = defaults.object(forKey: Keys.notesFontSize) as? Double ?? 14
    notesFloatsAboveOtherWindows = defaults.object(forKey: Keys.notesFloatsAboveOtherWindows) as? Bool ?? true
    notesOpenOnLaunch = defaults.bool(forKey: Keys.notesOpenOnLaunch)
    if defaults.object(forKey: Keys.notesHotkeyKeyCode) != nil {
      notesHotkey = Self.loadCombo(
        defaults,
        keyCodeKey: Keys.notesHotkeyKeyCode,
        modifiersKey: Keys.notesHotkeyModifiers,
        fallback: .defaultCombo
      )
    } else {
      notesHotkey = nil
    }

    filesSearchScope = defaults.string(forKey: Keys.filesSearchScope) ?? "this-mac"
    filesSearchContents = defaults.bool(forKey: Keys.filesSearchContents)
    filesMaxResults = defaults.object(forKey: Keys.filesMaxResults) as? Int ?? 50
    filesDefaultAction = defaults.string(forKey: Keys.filesDefaultAction) ?? "open"
    filesInlineResults = defaults.object(forKey: Keys.filesInlineResults) as? Bool ?? true
    filesExtraFolders = defaults.stringArray(forKey: Keys.filesExtraFolders) ?? []
    filesExcludedFolders = defaults.stringArray(forKey: Keys.filesExcludedFolders) ?? []
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
