import Foundation

/// Modifier keys of a shortcut. The four real modifiers held together are the Hyper key.
public struct KeyModifiers: OptionSet, Hashable, Sendable {
  public let rawValue: UInt8

  public init(rawValue: UInt8) {
    self.rawValue = rawValue
  }

  public static let control = KeyModifiers(rawValue: 1 << 0)
  public static let option = KeyModifiers(rawValue: 1 << 1)
  public static let shift = KeyModifiers(rawValue: 1 << 2)
  public static let command = KeyModifiers(rawValue: 1 << 3)

  /// Control + Option + Shift + Command, what the Hyper key produces while held.
  public static let hyper: KeyModifiers = [.control, .option, .shift, .command]

  public var isHyper: Bool {
    self == .hyper
  }

  // Carbon `EventModifiers` bits (cmdKey, shiftKey, optionKey, controlKey).
  private static let carbonCommand: UInt32 = 0x0100
  private static let carbonShift: UInt32 = 0x0200
  private static let carbonOption: UInt32 = 0x0800
  private static let carbonControl: UInt32 = 0x1000

  // Device-independent `CGEventFlags` masks.
  private static let cgShift: UInt64 = 0x0002_0000
  private static let cgControl: UInt64 = 0x0004_0000
  private static let cgOption: UInt64 = 0x0008_0000
  private static let cgCommand: UInt64 = 0x0010_0000

  public init(carbonModifiers: UInt32) {
    var value = KeyModifiers()
    if carbonModifiers & Self.carbonControl != 0 {
      value.insert(.control)
    }
    if carbonModifiers & Self.carbonOption != 0 {
      value.insert(.option)
    }
    if carbonModifiers & Self.carbonShift != 0 {
      value.insert(.shift)
    }
    if carbonModifiers & Self.carbonCommand != 0 {
      value.insert(.command)
    }
    self = value
  }

  public init(cgEventFlags: UInt64) {
    var value = KeyModifiers()
    if cgEventFlags & Self.cgControl != 0 {
      value.insert(.control)
    }
    if cgEventFlags & Self.cgOption != 0 {
      value.insert(.option)
    }
    if cgEventFlags & Self.cgShift != 0 {
      value.insert(.shift)
    }
    if cgEventFlags & Self.cgCommand != 0 {
      value.insert(.command)
    }
    self = value
  }

  public var carbonModifiers: UInt32 {
    var value: UInt32 = 0
    if contains(.control) {
      value |= Self.carbonControl
    }
    if contains(.option) {
      value |= Self.carbonOption
    }
    if contains(.shift) {
      value |= Self.carbonShift
    }
    if contains(.command) {
      value |= Self.carbonCommand
    }
    return value
  }

  public var cgEventFlags: UInt64 {
    var value: UInt64 = 0
    if contains(.control) {
      value |= Self.cgControl
    }
    if contains(.option) {
      value |= Self.cgOption
    }
    if contains(.shift) {
      value |= Self.cgShift
    }
    if contains(.command) {
      value |= Self.cgCommand
    }
    return value
  }

  /// "✦" for Hyper, otherwise the macOS glyphs in the standard ⌃⌥⇧⌘ order.
  public var symbols: String {
    if isHyper {
      return "✦"
    }
    var text = ""
    if contains(.control) {
      text += "⌃"
    }
    if contains(.option) {
      text += "⌥"
    }
    if contains(.shift) {
      text += "⇧"
    }
    if contains(.command) {
      text += "⌘"
    }
    return text
  }
}

extension KeyModifiers: Codable {
  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    try self.init(rawValue: container.decode(UInt8.self))
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}

/// A key code plus modifiers. Key codes are macOS virtual key codes (`kVK_*`).
public struct KeyShortcut: Hashable, Codable, Sendable {
  public var keyCode: UInt16
  public var modifiers: KeyModifiers

  public init(keyCode: UInt16, modifiers: KeyModifiers) {
    self.keyCode = keyCode
    self.modifiers = modifiers
  }

  /// Convenience for the built-in defaults, e.g. `KeyShortcut(.hyper, "left")`.
  public init?(_ modifiers: KeyModifiers, _ key: String) {
    guard let keyCode = KeyNames.keyCode(named: key) else {
      return nil
    }
    self.init(keyCode: keyCode, modifiers: modifiers)
  }

  public var isHyper: Bool {
    modifiers.isHyper
  }

  /// Bare keys can only be global shortcuts when they are function keys.
  public var isBindable: Bool {
    !modifiers.isEmpty || KeyNames.isFunctionKey(keyCode)
  }

  public var keyName: String {
    KeyNames.name(for: keyCode)
  }

  /// Human readable form, e.g. "✦←" or "⌃⌥⇧⌘Return" or "⌘⇧K".
  public var displayString: String {
    modifiers.symbols + keyName
  }

  /// Parses forms like "hyper+left", "cmd+shift+k", "ctrl-alt-delete", "⌃⌥⇧⌘Return", "✦←".
  public static func parse(_ text: String) -> KeyShortcut? {
    var modifiers = KeyModifiers()
    var keyToken: String?

    for token in tokenize(text) {
      if let modifier = KeyNames.modifier(named: token) {
        modifiers.formUnion(modifier)
      } else if keyToken == nil {
        keyToken = token
      } else {
        return nil
      }
    }

    guard let keyToken, let keyCode = KeyNames.keyCode(named: keyToken) else {
      return nil
    }
    return KeyShortcut(keyCode: keyCode, modifiers: modifiers)
  }

  private static func tokenize(_ text: String) -> [String] {
    var tokens: [String] = []
    for rawPiece in text.split(separator: "+") {
      let piece = rawPiece.filter { !$0.isWhitespace }
      guard !piece.isEmpty else {
        continue
      }
      var remainder = Substring(piece)
      while let first = remainder.first, KeyNames.modifier(named: String(first)) != nil, remainder.count > 1 {
        tokens.append(String(first))
        remainder = remainder.dropFirst()
      }
      let rest = String(remainder)
      if rest.count > 1, rest.contains("-"), !rest.hasSuffix("-") {
        tokens.append(contentsOf: rest.split(separator: "-").map(String.init))
      } else if !rest.isEmpty {
        tokens.append(rest)
      }
    }
    return tokens
  }
}

extension KeyShortcut: CustomStringConvertible {
  public var description: String {
    displayString
  }
}

/// ANSI key code table. Display names are the ones macOS shows in menus.
public enum KeyNames {
  private static let names: [UInt16: String] = [
    0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B",
    12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4",
    22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O",
    32: "U", 33: "[", 34: "I", 35: "P", 36: "Return", 37: "L", 38: "J", 39: "'", 40: "K",
    41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 48: "Tab", 49: "Space",
    50: "`", 51: "Delete", 53: "Esc", 64: "F17", 65: "Keypad .", 67: "Keypad *", 69: "Keypad +",
    71: "Clear", 75: "Keypad /", 76: "Enter", 78: "Keypad -", 79: "F18", 80: "F19", 81: "Keypad =",
    82: "Keypad 0", 83: "Keypad 1", 84: "Keypad 2", 85: "Keypad 3", 86: "Keypad 4", 87: "Keypad 5",
    88: "Keypad 6", 89: "Keypad 7", 90: "F20", 91: "Keypad 8", 92: "Keypad 9", 96: "F5", 97: "F6",
    98: "F7", 99: "F3", 100: "F8", 101: "F9", 103: "F11", 105: "F13", 106: "F16", 107: "F14",
    109: "F10", 111: "F12", 113: "F15", 114: "Help", 115: "Home", 116: "Page Up", 117: "⌦",
    118: "F4", 119: "End", 120: "F2", 121: "Page Down", 122: "F1", 123: "←", 124: "→", 125: "↓",
    126: "↑"
  ]

  private static let aliases: [String: UInt16] = [
    "left": 123, "leftarrow": 123, "arrowleft": 123,
    "right": 124, "rightarrow": 124, "arrowright": 124,
    "down": 125, "downarrow": 125, "arrowdown": 125,
    "up": 126, "uparrow": 126, "arrowup": 126,
    "return": 36, "↩": 36, "⏎": 36, "enter": 76,
    "tab": 48, "⇥": 48, "space": 49, "␣": 49,
    "esc": 53, "escape": 53, "⎋": 53,
    "delete": 51, "backspace": 51, "⌫": 51,
    "forwarddelete": 117, "fwddelete": 117, "⌦": 117,
    "home": 115, "↖": 115, "end": 119, "↘": 119,
    "pageup": 116, "pgup": 116, "⇞": 116, "pagedown": 121, "pgdn": 121, "⇟": 121,
    "help": 114, "clear": 71,
    "minus": 27, "equals": 24, "equal": 24, "comma": 43, "period": 47, "slash": 44,
    "backslash": 42, "semicolon": 41, "quote": 39, "grave": 50, "backtick": 50,
    "leftbracket": 33, "rightbracket": 30
  ]

  private static let modifierNames: [String: KeyModifiers] = [
    "ctrl": .control, "control": .control, "⌃": .control, "^": .control,
    "opt": .option, "option": .option, "alt": .option, "⌥": .option,
    "shift": .shift, "⇧": .shift,
    "cmd": .command, "command": .command, "⌘": .command,
    "hyper": .hyper, "✦": .hyper
  ]

  private static let functionKeys: Set<UInt16> = [
    122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90
  ]

  private static let codesByLowercaseName: [String: UInt16] = {
    var table: [String: UInt16] = [:]
    for (code, name) in names {
      table[name.lowercased()] = code
      table[name.lowercased().replacingOccurrences(of: " ", with: "")] = code
    }
    for (alias, code) in aliases {
      table[alias] = code
    }
    return table
  }()

  public static func name(for keyCode: UInt16) -> String {
    names[keyCode] ?? "Key \(keyCode)"
  }

  public static func keyCode(named name: String) -> UInt16? {
    let key = name.trimmingCharacters(in: .whitespaces).lowercased()
    if let code = codesByLowercaseName[key] {
      return code
    }
    if key.hasPrefix("key "), let code = UInt16(key.dropFirst(4)) {
      return code
    }
    return nil
  }

  public static func modifier(named name: String) -> KeyModifiers? {
    modifierNames[name.lowercased()]
  }

  public static func isFunctionKey(_ keyCode: UInt16) -> Bool {
    functionKeys.contains(keyCode)
  }
}
