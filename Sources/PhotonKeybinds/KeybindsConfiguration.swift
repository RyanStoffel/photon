import Foundation

/// Physical key that becomes the Hyper key. All but `.f18` are remapped to F18 at the HID level.
public enum HyperKeySource: String, CaseIterable, Codable, Sendable, Identifiable {
  case capsLock
  case rightCommand
  case rightOption
  case rightControl
  case rightShift
  case section
  case f18

  public var id: String {
    rawValue
  }

  public var title: String {
    switch self {
    case .capsLock: "Caps Lock"
    case .rightCommand: "Right Command"
    case .rightOption: "Right Option"
    case .rightControl: "Right Control"
    case .rightShift: "Right Shift"
    case .section: "Section (§)"
    case .f18: "F18 (no remap)"
    }
  }

  /// HID usage (page 0x07 keyboard) of the physical key; `nil` when no remap is needed.
  public var hidUsage: UInt64? {
    switch self {
    case .capsLock: 0x7_0000_0039
    case .rightCommand: 0x7_0000_00e7
    case .rightOption: 0x7_0000_00e6
    case .rightControl: 0x7_0000_00e4
    case .rightShift: 0x7_0000_00e5
    case .section: 0x7_0000_0064
    case .f18: nil
    }
  }

  /// HID usage of F18, the key every source is remapped to.
  public static let destinationUsage: UInt64 = 0x7_0000_006d

  /// Virtual key code of F18, what the event tap watches for.
  public static let destinationKeyCode: UInt16 = 79
}

/// What a quick press of the Hyper key (without another key) does.
public enum HyperTapBehavior: String, CaseIterable, Codable, Sendable, Identifiable {
  case nothing
  case escape
  case capsLock

  public var id: String {
    rawValue
  }

  public var title: String {
    switch self {
    case .nothing: "Do nothing"
    case .escape: "Escape"
    case .capsLock: "Toggle Caps Lock"
    }
  }
}

public struct HyperKeySettings: Codable, Equatable, Sendable {
  public var enabled: Bool
  public var source: HyperKeySource
  public var tapBehavior: HyperTapBehavior

  public init(enabled: Bool = true, source: HyperKeySource = .capsLock, tapBehavior: HyperTapBehavior = .nothing) {
    self.enabled = enabled
    self.source = source
    self.tapBehavior = tapBehavior
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    source = try container.decodeIfPresent(HyperKeySource.self, forKey: .source) ?? .capsLock
    tapBehavior = try container.decodeIfPresent(HyperTapBehavior.self, forKey: .tapBehavior) ?? .nothing
  }
}

/// A shortcut that launches, focuses, or hides one application.
public struct AppHotkey: Codable, Equatable, Identifiable, Sendable {
  public var id: UUID
  public var bundleIdentifier: String
  public var name: String
  public var shortcut: KeyShortcut?

  public init(id: UUID = UUID(), bundleIdentifier: String, name: String, shortcut: KeyShortcut? = nil) {
    self.id = id
    self.bundleIdentifier = bundleIdentifier
    self.name = name
    self.shortcut = shortcut
  }
}

public struct WindowBinding: Codable, Equatable, Identifiable, Sendable {
  public var action: WindowAction
  public var shortcut: KeyShortcut?

  public init(action: WindowAction, shortcut: KeyShortcut?) {
    self.action = action
    self.shortcut = shortcut
  }

  public var id: WindowAction {
    action
  }
}

/// Who owns a shortcut, for conflict reporting.
public enum BindingOwner: Hashable, Sendable {
  case launcher
  case app(UUID)
  case window(WindowAction)
}

public struct ShortcutConflict: Hashable, Sendable {
  public let shortcut: KeyShortcut
  public let owners: [BindingOwner]
}

/// Everything on the Keybinds settings tab. Persisted as JSON by `SettingsStore`.
public struct KeybindsConfiguration: Codable, Equatable, Sendable {
  public var hyperKey: HyperKeySettings
  public var appHotkeys: [AppHotkey]
  public var windowBindings: [WindowBinding]

  public init(
    hyperKey: HyperKeySettings = HyperKeySettings(),
    appHotkeys: [AppHotkey] = [],
    windowBindings: [WindowBinding] = KeybindsConfiguration.defaultWindowBindings
  ) {
    self.hyperKey = hyperKey
    self.appHotkeys = appHotkeys
    self.windowBindings = windowBindings
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    hyperKey = try container.decodeIfPresent(HyperKeySettings.self, forKey: .hyperKey) ?? HyperKeySettings()
    appHotkeys = try container.decodeIfPresent([AppHotkey].self, forKey: .appHotkeys) ?? []
    windowBindings = try container.decodeIfPresent([WindowBinding].self, forKey: .windowBindings)
      ?? Self.defaultWindowBindings
    self = normalized()
  }

  public static let `default` = KeybindsConfiguration()

  public static var defaultWindowBindings: [WindowBinding] {
    WindowAction.allCases.map { WindowBinding(action: $0, shortcut: $0.defaultShortcut) }
  }

  /// One binding per action, in canonical order. Actions missing from stored data get their default shortcut.
  public func normalized() -> KeybindsConfiguration {
    var copy = self
    var byAction: [WindowAction: WindowBinding] = [:]
    for binding in windowBindings where byAction[binding.action] == nil {
      byAction[binding.action] = binding
    }
    copy.windowBindings = WindowAction.allCases.map {
      byAction[$0] ?? WindowBinding(action: $0, shortcut: $0.defaultShortcut)
    }
    return copy
  }

  public func shortcut(for action: WindowAction) -> KeyShortcut? {
    windowBindings.first { $0.action == action }?.shortcut
  }

  public mutating func setShortcut(_ shortcut: KeyShortcut?, for action: WindowAction) {
    if let index = windowBindings.firstIndex(where: { $0.action == action }) {
      windowBindings[index].shortcut = shortcut
    } else {
      windowBindings.append(WindowBinding(action: action, shortcut: shortcut))
    }
  }

  public mutating func resetWindowBindings() {
    windowBindings = Self.defaultWindowBindings
  }

  /// Shortcuts used by more than one owner. `launcher` is the launcher hotkey from the General tab.
  public func conflicts(launcher: KeyShortcut? = nil) -> [ShortcutConflict] {
    var owners: [KeyShortcut: [BindingOwner]] = [:]
    var order: [KeyShortcut] = []

    func add(_ shortcut: KeyShortcut?, _ owner: BindingOwner) {
      guard let shortcut else {
        return
      }
      if owners[shortcut] == nil {
        order.append(shortcut)
      }
      owners[shortcut, default: []].append(owner)
    }

    add(launcher, .launcher)
    for hotkey in appHotkeys {
      add(hotkey.shortcut, .app(hotkey.id))
    }
    for binding in windowBindings {
      add(binding.shortcut, .window(binding.action))
    }

    return order.compactMap { shortcut in
      guard let list = owners[shortcut], list.count > 1 else {
        return nil
      }
      return ShortcutConflict(shortcut: shortcut, owners: list)
    }
  }

  /// Every owner that takes part in a conflict; handy for marking rows in the UI.
  public func conflictingOwners(launcher: KeyShortcut? = nil) -> Set<BindingOwner> {
    Set(conflicts(launcher: launcher).flatMap(\.owners))
  }
}
