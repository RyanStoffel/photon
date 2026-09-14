import AppKit
import Carbon

public struct HotkeyCombo: Equatable, Sendable {
  public var keyCode: UInt32
  public var carbonModifiers: UInt32

  public init(keyCode: UInt32, carbonModifiers: UInt32) {
    self.keyCode = keyCode
    self.carbonModifiers = carbonModifiers
  }

  public static let defaultCombo = HotkeyCombo(
    keyCode: UInt32(kVK_Space),
    carbonModifiers: UInt32(cmdKey)
  )

  public var displayString: String {
    modifierSymbols + keyName
  }

  public var appleFlags: UInt32 {
    var flags: UInt32 = 0
    if carbonModifiers & UInt32(cmdKey) != 0 {
      flags |= UInt32(NSEvent.ModifierFlags.command.rawValue)
    }
    if carbonModifiers & UInt32(shiftKey) != 0 {
      flags |= UInt32(NSEvent.ModifierFlags.shift.rawValue)
    }
    if carbonModifiers & UInt32(optionKey) != 0 {
      flags |= UInt32(NSEvent.ModifierFlags.option.rawValue)
    }
    if carbonModifiers & UInt32(controlKey) != 0 {
      flags |= UInt32(NSEvent.ModifierFlags.control.rawValue)
    }
    return flags
  }

  public static func carbonModifiers(fromApple flags: UInt32) -> UInt32 {
    var carbon: UInt32 = 0
    if flags & UInt32(NSEvent.ModifierFlags.command.rawValue) != 0 {
      carbon |= UInt32(cmdKey)
    }
    if flags & UInt32(NSEvent.ModifierFlags.shift.rawValue) != 0 {
      carbon |= UInt32(shiftKey)
    }
    if flags & UInt32(NSEvent.ModifierFlags.option.rawValue) != 0 {
      carbon |= UInt32(optionKey)
    }
    if flags & UInt32(NSEvent.ModifierFlags.control.rawValue) != 0 {
      carbon |= UInt32(controlKey)
    }
    return carbon
  }

  private var modifierSymbols: String {
    var parts = ""
    if carbonModifiers & UInt32(controlKey) != 0 {
      parts += "⌃"
    }
    if carbonModifiers & UInt32(optionKey) != 0 {
      parts += "⌥"
    }
    if carbonModifiers & UInt32(shiftKey) != 0 {
      parts += "⇧"
    }
    if carbonModifiers & UInt32(cmdKey) != 0 {
      parts += "⌘"
    }
    return parts
  }

  private var keyName: String {
    switch Int(keyCode) {
    case kVK_Space: return "Space"
    case kVK_Tab: return "Tab"
    case kVK_Return: return "Return"
    case kVK_Escape: return "Esc"
    case kVK_Delete: return "Delete"
    case kVK_ForwardDelete: return "Fwd Delete"
    case kVK_LeftArrow: return "Left"
    case kVK_RightArrow: return "Right"
    case kVK_UpArrow: return "Up"
    case kVK_DownArrow: return "Down"
    case kVK_F1: return "F1"
    case kVK_F2: return "F2"
    case kVK_F3: return "F3"
    case kVK_F4: return "F4"
    case kVK_F5: return "F5"
    case kVK_F6: return "F6"
    case kVK_F7: return "F7"
    case kVK_F8: return "F8"
    case kVK_F9: return "F9"
    case kVK_F10: return "F10"
    case kVK_F11: return "F11"
    case kVK_F12: return "F12"
    default:
      let raw = keyCodeString()
      return raw.isEmpty ? "Key \(keyCode)" : raw
    }
  }

  private func keyCodeString() -> String {
    let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource().takeRetainedValue()
    guard let rawPtr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
      return ""
    }
    let data = Unmanaged<CFData>.fromOpaque(rawPtr).takeUnretainedValue() as Data
    return data.withUnsafeBytes { buffer -> String in
      guard let base = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
        return ""
      }
      var keysDown: UInt32 = 0
      var chars: [UniChar] = [0, 0, 0, 0]
      var length = 0
      let err = UCKeyTranslate(
        base,
        UInt16(keyCode),
        UInt16(kUCKeyActionDisplay),
        0,
        UInt32(LMGetKbdType()),
        OptionBits(kUCKeyTranslateNoDeadKeysBit),
        &keysDown,
        chars.count,
        &length,
        &chars
      )
      guard err == noErr, length > 0 else {
        return ""
      }
      return String(utf16CodeUnits: chars, count: length).uppercased()
    }
  }
}
