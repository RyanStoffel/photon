import Foundation

public struct GlobalHotkeyToken: Hashable, Sendable {
  public let rawValue: UInt32

  public init(rawValue: UInt32) {
    self.rawValue = rawValue
  }
}

/// Registers system-wide shortcuts for plain modifier combinations. The app supplies an
/// implementation backed by Carbon `RegisterEventHotKey` (its `HotkeyManager`).
@MainActor
public protocol GlobalHotkeyRegistrar: AnyObject {
  func register(_ shortcut: KeyShortcut, action: @escaping @MainActor () -> Void) throws -> GlobalHotkeyToken
  func unregister(_ token: GlobalHotkeyToken)
}
