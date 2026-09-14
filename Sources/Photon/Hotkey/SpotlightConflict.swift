import AppKit

enum SpotlightConflict {
  static let spotlightHotKeyID = "64"
  private static let shownKey = "hasShownSpotlightGuidance"

  static func conflicts(with combo: HotkeyCombo) -> Bool {
    let url = URL(
      fileURLWithPath: NSHomeDirectory() + "/Library/Preferences/com.apple.symbolichotkeys.plist"
    )
    guard let root = NSDictionary(contentsOf: url),
          let keys = root["AppleSymbolicHotKeys"] as? NSDictionary,
          let spotlight = keys[spotlightHotKeyID] as? NSDictionary,
          (spotlight["enabled"] as? Bool) == true,
          let value = spotlight["value"] as? NSDictionary,
          let parameters = value["parameters"] as? [Any],
          parameters.count >= 3
    else {
      return false
    }

    let keyCode = intValue(parameters[1])
    let modifiers = UInt32(truncatingIfNeeded: intValue(parameters[2]))
    guard keyCode == Int(combo.keyCode) else {
      return false
    }

    if modifiers == combo.carbonModifiers {
      return true
    }
    if modifiers == combo.appleFlags {
      return true
    }
    if HotkeyCombo.carbonModifiers(fromApple: modifiers) == combo.carbonModifiers {
      return true
    }
    return false
  }

  static func adviseIfNeeded(current combo: HotkeyCombo) {
    let defaults = UserDefaults.standard
    guard !defaults.bool(forKey: shownKey) else {
      return
    }
    defaults.set(true, forKey: shownKey)
    guard conflicts(with: combo) else {
      return
    }

    let alert = NSAlert()
    alert.messageText = "Photon and Spotlight share the same shortcut"
    alert.informativeText = """
    Photon defaults to \(combo.displayString), which is also Spotlight’s shortcut.

    To use Photon without a fight:
    1. Open System Settings > Keyboard > Keyboard Shortcuts
    2. Select Spotlight
    3. Uncheck “Show Spotlight search”

    You can change Photon’s shortcut later in Settings > General.
    """
    alert.alertStyle = .informational
    alert.addButton(withTitle: "Open Keyboard Settings")
    alert.addButton(withTitle: "Later")
    let response = alert.runModal()
    if response == .alertFirstButtonReturn {
      openKeyboardSettings()
    }
  }

  static func openKeyboardSettings() {
    let urls = [
      "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?Shortcuts",
      "x-apple.systempreferences:com.apple.preference.keyboard?Shortcuts"
    ]
    for string in urls {
      if let url = URL(string: string), NSWorkspace.shared.open(url) {
        return
      }
    }
  }

  private static func intValue(_ value: Any) -> Int {
    if let number = value as? NSNumber {
      return number.intValue
    }
    if let int = value as? Int {
      return int
    }
    return -1
  }
}
