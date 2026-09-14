import Carbon
import Foundation

enum HotkeyError: Error, Sendable {
  case registrationFailed(OSStatus)
}

private let photonHotKeySignature: OSType = 0x5048_544e

/// Abstraction over Carbon `RegisterEventHotKey`.
@MainActor
final class HotkeyManager {
  static let shared = HotkeyManager()

  var onPressed: (() -> Void)?

  private var hotKeyRef: EventHotKeyRef?
  private var handlerRef: EventHandlerRef?

  private init() {}

  func register(combo: HotkeyCombo) throws {
    unregister()

    var hotKeyID = EventHotKeyID(signature: photonHotKeySignature, id: 1)
    var status = RegisterEventHotKey(
      combo.keyCode,
      combo.carbonModifiers,
      hotKeyID,
      GetEventDispatcherTarget(),
      0,
      &hotKeyRef
    )
    guard status == noErr else {
      throw HotkeyError.registrationFailed(status)
    }

    var spec = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: UInt32(kEventHotKeyPressed)
    )
    status = InstallEventHandler(
      GetEventDispatcherTarget(),
      photonHotKeyHandler,
      1,
      &spec,
      nil,
      &handlerRef
    )
    guard status == noErr else {
      unregister()
      throw HotkeyError.registrationFailed(status)
    }
  }

  func unregister() {
    if let hotKeyRef {
      UnregisterEventHotKey(hotKeyRef)
      self.hotKeyRef = nil
    }
    if let handlerRef {
      RemoveEventHandler(handlerRef)
      self.handlerRef = nil
    }
  }

  func handlePress() {
    onPressed?()
  }
}

private func photonHotKeyHandler(
  _: EventHandlerCallRef?,
  _ event: EventRef?,
  _: UnsafeMutableRawPointer?
) -> OSStatus {
  var hotKeyID = EventHotKeyID()
  let status = GetEventParameter(
    event,
    EventParamName(kEventParamDirectObject),
    EventParamType(typeEventHotKeyID),
    nil,
    MemoryLayout<EventHotKeyID>.size,
    nil,
    &hotKeyID
  )
  if status == noErr, hotKeyID.signature == photonHotKeySignature {
    Task { @MainActor in
      HotkeyManager.shared.handlePress()
    }
  }
  return noErr
}
