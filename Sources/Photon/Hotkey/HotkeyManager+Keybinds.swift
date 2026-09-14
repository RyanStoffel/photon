import PhotonKeybinds

/// Lets `PhotonKeybinds` register plain shortcuts through the app's Carbon hotkey manager.
extension HotkeyManager: GlobalHotkeyRegistrar {
  func register(_ shortcut: KeyShortcut, action: @escaping () -> Void) throws -> GlobalHotkeyToken {
    let id = try add(combo: shortcut.hotkeyCombo, handler: action)
    return GlobalHotkeyToken(rawValue: id)
  }

  func unregister(_ token: GlobalHotkeyToken) {
    unregister(id: token.rawValue)
  }
}

extension KeyShortcut {
  init(_ combo: HotkeyCombo) {
    self.init(
      keyCode: UInt16(truncatingIfNeeded: combo.keyCode),
      modifiers: KeyModifiers(carbonModifiers: combo.carbonModifiers)
    )
  }

  var hotkeyCombo: HotkeyCombo {
    HotkeyCombo(keyCode: UInt32(keyCode), carbonModifiers: modifiers.carbonModifiers)
  }
}
