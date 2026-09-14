import Carbon
import Foundation

enum HotkeyError: Error, Sendable {
  case registrationFailed(OSStatus)
}

private let photonHotKeySignature: OSType = 0x5048_544e

/// Abstraction over Carbon `RegisterEventHotKey`.
///
/// Id `1` is the launcher shortcut (`register(combo:)` / `onPressed`). Features
/// register additional shortcuts with their own id and handler, or ask for a
/// fresh id with `add(combo:handler:)` when the number of shortcuts is dynamic.
@MainActor
final class HotkeyManager {
  static let shared = HotkeyManager()

  /// Well-known ids. Keep them unique across features.
  enum HotkeyID {
    static let launcher: UInt32 = 1
    static let clipboard: UInt32 = 2
    static let notes: UInt32 = 3
    /// Ids handed out by `add(combo:handler:)` start here.
    static let firstDynamic: UInt32 = 1000
  }

  var onPressed: (() -> Void)?

  private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
  private var handlers: [UInt32: () -> Void] = [:]
  private var handlerRef: EventHandlerRef?
  private var nextDynamicID = HotkeyID.firstDynamic

  private init() {}

  /// Registers the launcher shortcut, replacing the previous one.
  func register(combo: HotkeyCombo) throws {
    try register(combo: combo, id: HotkeyID.launcher) { [weak self] in
      self?.onPressed?()
    }
  }

  /// Registers (or replaces) the shortcut for `id`.
  func register(combo: HotkeyCombo, id: UInt32, handler: @escaping () -> Void) throws {
    unregister(id: id)
    try installHandlerIfNeeded()

    let hotKeyID = EventHotKeyID(signature: photonHotKeySignature, id: id)
    var ref: EventHotKeyRef?
    let status = RegisterEventHotKey(
      combo.keyCode,
      combo.carbonModifiers,
      hotKeyID,
      GetEventDispatcherTarget(),
      0,
      &ref
    )
    guard status == noErr, let ref else {
      throw HotkeyError.registrationFailed(status)
    }
    hotKeyRefs[id] = ref
    handlers[id] = handler
  }

  /// Registers a shortcut under a fresh id and returns that id for `unregister(id:)`.
  func add(combo: HotkeyCombo, handler: @escaping () -> Void) throws -> UInt32 {
    let id = nextDynamicID
    try register(combo: combo, id: id, handler: handler)
    nextDynamicID += 1
    return id
  }

  /// Unregisters the launcher shortcut.
  func unregister() {
    unregister(id: HotkeyID.launcher)
  }

  func unregister(id: UInt32) {
    if let ref = hotKeyRefs.removeValue(forKey: id) {
      UnregisterEventHotKey(ref)
    }
    handlers[id] = nil
    if hotKeyRefs.isEmpty, let handlerRef {
      RemoveEventHandler(handlerRef)
      self.handlerRef = nil
    }
  }

  func unregisterAll() {
    for id in Array(hotKeyRefs.keys) {
      unregister(id: id)
    }
  }

  func handlePress(id: UInt32) {
    handlers[id]?()
  }

  private func installHandlerIfNeeded() throws {
    guard handlerRef == nil else {
      return
    }
    var spec = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: UInt32(kEventHotKeyPressed)
    )
    let status = InstallEventHandler(
      GetEventDispatcherTarget(),
      photonHotKeyHandler,
      1,
      &spec,
      nil,
      &handlerRef
    )
    guard status == noErr else {
      throw HotkeyError.registrationFailed(status)
    }
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
    let id = hotKeyID.id
    Task { @MainActor in
      HotkeyManager.shared.handlePress(id: id)
    }
  }
  return noErr
}
