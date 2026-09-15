import CoreGraphics
import Foundation

/// Turns the (HID-remapped) Hyper key into Control + Option + Shift + Command while it is held.
///
/// A session-level `CGEventTap` swallows the Hyper key itself, adds the four modifier flags to every
/// key event typed while it is down, and dispatches keys that have a Hyper shortcut bound in Photon.
/// A quick press without another key runs the configured tap behaviour.
///
/// The tap runs on the main run loop; state is guarded by a lock because the callback is plain C.
public final class HyperKeyEngine: @unchecked Sendable {
  public struct Configuration: Equatable, Sendable {
    public var hyperKeyCode: UInt16
    public var tapBehavior: HyperTapBehavior
    /// Keys with a Hyper shortcut. They are swallowed and reported through `onHyperShortcut`.
    public var boundKeyCodes: Set<UInt16>
    public var tapThreshold: TimeInterval

    public init(
      hyperKeyCode: UInt16 = HyperKeySource.destinationKeyCode,
      tapBehavior: HyperTapBehavior = .nothing,
      boundKeyCodes: Set<UInt16> = [],
      tapThreshold: TimeInterval = 0.4
    ) {
      self.hyperKeyCode = hyperKeyCode
      self.tapBehavior = tapBehavior
      self.boundKeyCodes = boundKeyCodes
      self.tapThreshold = tapThreshold
    }
  }

  public enum StartError: LocalizedError {
    case tapCreationFailed

    public var errorDescription: String? {
      "macOS refused to create the keyboard event tap. Grant Photon Accessibility access and try again."
    }
  }

  private enum Decision {
    case pass
    case swallow
    case shortcut(UInt16)
    case tap(HyperTapBehavior)
  }

  private static var hyperFlags: CGEventFlags {
    CGEventFlags(rawValue: KeyModifiers.hyper.cgEventFlags)
  }

  /// Called on the main queue with the key code of a bound Hyper shortcut.
  public var onHyperShortcut: (@Sendable (UInt16) -> Void)? {
    get { lock.withLock { shortcutHandler } }
    set { lock.withLock { shortcutHandler = newValue } }
  }

  private let lock = NSLock()
  private var shortcutHandler: (@Sendable (UInt16) -> Void)?
  private var configuration = Configuration()
  private var tap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  private var suspended = false

  private var hyperDown = false
  private var hyperUsed = false
  private var hyperDownAt: TimeInterval = 0
  private var modifiedKeys = Set<Int64>()
  private var swallowedKeys = Set<Int64>()

  public init() {}

  deinit {
    stop()
  }

  public var isRunning: Bool {
    lock.withLock { tap != nil }
  }

  public func update(_ configuration: Configuration) {
    lock.withLock { self.configuration = configuration }
  }

  /// While suspended (a shortcut recorder is active) Hyper still adds modifier flags, but bound keys
  /// are passed through instead of being dispatched, so they can be recorded.
  public func setSuspended(_ suspended: Bool) {
    lock.withLock { self.suspended = suspended }
  }

  public func start() throws {
    lock.lock()
    defer { lock.unlock() }
    guard tap == nil else {
      return
    }
    let mask = CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.keyUp.rawValue)
    guard let port = CGEvent.tapCreate(
      tap: .cgSessionEventTap,
      place: .headInsertEventTap,
      options: .defaultTap,
      eventsOfInterest: mask,
      callback: hyperKeyTapCallback,
      userInfo: Unmanaged.passUnretained(self).toOpaque()
    ) else {
      throw StartError.tapCreationFailed
    }
    let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    CGEvent.tapEnable(tap: port, enable: true)
    tap = port
    runLoopSource = source
    resetState()
  }

  public func stop() {
    lock.lock()
    defer { lock.unlock() }
    if let tap {
      CGEvent.tapEnable(tap: tap, enable: false)
      CFMachPortInvalidate(tap)
    }
    if let runLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
    }
    tap = nil
    runLoopSource = nil
    resetState()
  }

  fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      if let tap = lock.withLock({ tap }) {
        CGEvent.tapEnable(tap: tap, enable: true)
      }
      return Unmanaged.passUnretained(event)
    }
    guard type == .keyDown || type == .keyUp else {
      return Unmanaged.passUnretained(event)
    }

    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
    let decision = decide(type: type, keyCode: keyCode, isRepeat: isRepeat, event: event)

    switch decision {
    case .pass:
      return Unmanaged.passUnretained(event)
    case .swallow:
      return nil
    case let .shortcut(code):
      if let handler = onHyperShortcut {
        DispatchQueue.main.async { handler(code) }
      }
      return nil
    case let .tap(behavior):
      DispatchQueue.main.async { Self.performTap(behavior) }
      return nil
    }
  }

  private func decide(type: CGEventType, keyCode: Int64, isRepeat: Bool, event: CGEvent) -> Decision {
    lock.lock()
    defer { lock.unlock() }

    if keyCode == Int64(configuration.hyperKeyCode) {
      return handleHyperKey(down: type == .keyDown, isRepeat: isRepeat)
    }

    if type == .keyDown {
      guard hyperDown else {
        return .pass
      }
      hyperUsed = true
      if !suspended, configuration.boundKeyCodes.contains(UInt16(truncatingIfNeeded: keyCode)) {
        swallowedKeys.insert(keyCode)
        return isRepeat ? .swallow : .shortcut(UInt16(truncatingIfNeeded: keyCode))
      }
      event.flags.formUnion(Self.hyperFlags)
      modifiedKeys.insert(keyCode)
      return .pass
    }

    if swallowedKeys.remove(keyCode) != nil {
      return .swallow
    }
    if modifiedKeys.remove(keyCode) != nil {
      event.flags.formUnion(Self.hyperFlags)
    }
    return .pass
  }

  private func handleHyperKey(down: Bool, isRepeat: Bool) -> Decision {
    if down {
      if !hyperDown, !isRepeat {
        hyperDown = true
        hyperUsed = false
        hyperDownAt = ProcessInfo.processInfo.systemUptime
      }
      return .swallow
    }
    let wasDown = hyperDown
    hyperDown = false
    let held = ProcessInfo.processInfo.systemUptime - hyperDownAt
    if wasDown, !hyperUsed, held < configuration.tapThreshold, configuration.tapBehavior != .nothing {
      return .tap(configuration.tapBehavior)
    }
    return .swallow
  }

  private func resetState() {
    hyperDown = false
    hyperUsed = false
    modifiedKeys.removeAll()
    swallowedKeys.removeAll()
  }

  private static func performTap(_ behavior: HyperTapBehavior) {
    switch behavior {
    case .nothing:
      break
    case .escape:
      postKey(53)
    case .capsLock:
      CapsLockState.toggle()
    }
  }

  private static func postKey(_ keyCode: CGKeyCode) {
    guard let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
          let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
    else {
      return
    }
    down.post(tap: .cghidEventTap)
    up.post(tap: .cghidEventTap)
  }
}

private func hyperKeyTapCallback(
  proxy _: CGEventTapProxy,
  type: CGEventType,
  event: CGEvent,
  userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
  guard let userInfo else {
    return Unmanaged.passUnretained(event)
  }
  let engine = Unmanaged<HyperKeyEngine>.fromOpaque(userInfo).takeUnretainedValue()
  return engine.handle(type: type, event: event)
}
