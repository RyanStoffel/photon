import AppKit
import ApplicationServices

public enum WindowManagerError: LocalizedError {
  case accessibilityDenied
  case noFrontmostApplication
  case noFocusedWindow
  case noScreen
  case nothingToRestore
  case attributeFailed(AXError)

  public var errorDescription: String? {
    switch self {
    case .accessibilityDenied:
      "Window management needs Accessibility access. Grant it in System Settings > Privacy & Security."
    case .noFrontmostApplication:
      "No frontmost application."
    case .noFocusedWindow:
      "The frontmost application has no focused window."
    case .noScreen:
      "Could not determine which display the window is on."
    case .nothingToRestore:
      "Photon has not moved this window yet."
    case let .attributeFailed(error):
      "The application rejected the window change (AXError \(error.rawValue))."
    }
  }
}

/// Moves and resizes the frontmost application's focused window through the Accessibility API.
@MainActor
public final class WindowManager {
  private static let enhancedUserInterfaceAttribute = "AXEnhancedUserInterface"
  private static let historyLimit = 32

  private struct HistoryEntry {
    let key: WindowKey
    /// Frame the window had before Photon's first change (until the user moves it by hand).
    var original: CGRect
    /// Frame Photon last applied, used to detect manual moves in between.
    var lastApplied: CGRect
  }

  private var history: [HistoryEntry] = []

  public init() {}

  public func perform(_ action: WindowAction) throws {
    guard AccessibilityPermission.isTrusted else {
      throw WindowManagerError.accessibilityDenied
    }
    guard let app = NSWorkspace.shared.frontmostApplication else {
      throw WindowManagerError.noFrontmostApplication
    }
    let application = AXUIElementCreateApplication(app.processIdentifier)
    AXUIElementSetMessagingTimeout(application, 1.0)
    guard let window = focusedWindow(of: application), let axFrame = frame(of: window) else {
      throw WindowManagerError.noFocusedWindow
    }
    guard let primaryHeight = NSScreen.screens.first?.frame.height else {
      throw WindowManagerError.noScreen
    }

    let current = WindowLayout.flipped(axFrame, primaryHeight: primaryHeight)
    guard let target = try targetFrame(for: action, window: window, current: current) else {
      return
    }
    if action != .restore {
      recordChange(of: window, from: current, to: target)
    }
    try setFrame(WindowLayout.flipped(target, primaryHeight: primaryHeight), of: window, in: application)
  }

  /// Target frame in bottom-left coordinates, or `nil` when the action has nothing to do.
  private func targetFrame(for action: WindowAction, window: AXUIElement, current: CGRect) throws -> CGRect? {
    let screens = NSScreen.screens
    guard !screens.isEmpty else {
      throw WindowManagerError.noScreen
    }
    let frames = screens.map(\.frame)
    let screenIndex = WindowLayout.screenIndex(for: current, screens: frames)
      ?? screens.firstIndex { $0 == NSScreen.main } ?? 0
    let visible = screens[screenIndex].visibleFrame

    switch action {
    case .nextDisplay, .previousDisplay:
      let step = action == .nextDisplay ? 1 : -1
      let destination = WindowLayout.displayIndex(from: screenIndex, step: step, screens: frames)
      return WindowLayout.translate(current, from: visible, to: screens[destination].visibleFrame)
    case .restore:
      guard let previous = restoreFrame(for: window, current: current) else {
        throw WindowManagerError.nothingToRestore
      }
      return previous
    default:
      return WindowLayout.frame(for: action, window: current, in: visible)
    }
  }

  // MARK: - History

  /// Frame to go back to, or `nil` when Photon has not touched this window. A second restore toggles back.
  private func restoreFrame(for window: AXUIElement, current: CGRect) -> CGRect? {
    let key = WindowKey(element: window)
    guard let index = history.firstIndex(where: { $0.key == key }) else {
      return nil
    }
    let original = history[index].original
    history[index].original = current
    history[index].lastApplied = original
    return original
  }

  private func recordChange(of window: AXUIElement, from current: CGRect, to target: CGRect) {
    let key = WindowKey(element: window)
    if let index = history.firstIndex(where: { $0.key == key }) {
      var entry = history.remove(at: index)
      if !Self.approximatelyEqual(entry.lastApplied, current) {
        entry.original = current
      }
      entry.lastApplied = target
      history.append(entry)
    } else {
      history.append(HistoryEntry(key: key, original: current, lastApplied: target))
    }
    if history.count > Self.historyLimit {
      history.removeFirst(history.count - Self.historyLimit)
    }
  }

  private static func approximatelyEqual(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat = 2) -> Bool {
    abs(lhs.minX - rhs.minX) <= tolerance && abs(lhs.minY - rhs.minY) <= tolerance
      && abs(lhs.width - rhs.width) <= tolerance && abs(lhs.height - rhs.height) <= tolerance
  }

  // MARK: - Accessibility plumbing

  private func focusedWindow(of application: AXUIElement) -> AXUIElement? {
    if let window = element(application, kAXFocusedWindowAttribute) {
      return window
    }
    if let window = element(application, kAXMainWindowAttribute) {
      return window
    }
    guard let raw = copy(application, kAXWindowsAttribute), let list = raw as? [AnyObject] else {
      return nil
    }
    return list.lazy.compactMap { Self.asElement($0) }.first
  }

  private func frame(of window: AXUIElement) -> CGRect? {
    var origin = CGPoint.zero
    var size = CGSize.zero
    guard let position = copy(window, kAXPositionAttribute), Self.read(position, .cgPoint, into: &origin),
          let extent = copy(window, kAXSizeAttribute), Self.read(extent, .cgSize, into: &size)
    else {
      return nil
    }
    return CGRect(origin: origin, size: size)
  }

  /// Sets size, then position, then size again: some apps clamp the size until the window has moved.
  private func setFrame(_ frame: CGRect, of window: AXUIElement, in application: AXUIElement) throws {
    let enhanced = isEnhancedUserInterface(application)
    if enhanced {
      setEnhancedUserInterface(application, false)
    }
    defer {
      if enhanced {
        setEnhancedUserInterface(application, true)
      }
    }

    var size = frame.size
    var origin = frame.origin
    try set(window, kAXSizeAttribute, value: AXValueCreate(.cgSize, &size))
    try set(window, kAXPositionAttribute, value: AXValueCreate(.cgPoint, &origin))
    try set(window, kAXSizeAttribute, value: AXValueCreate(.cgSize, &size))
  }

  private func isEnhancedUserInterface(_ application: AXUIElement) -> Bool {
    guard let raw = copy(application, Self.enhancedUserInterfaceAttribute),
          CFGetTypeID(raw) == CFBooleanGetTypeID()
    else {
      return false
    }
    return CFBooleanGetValue(unsafeDowncast(raw, to: CFBoolean.self))
  }

  private func setEnhancedUserInterface(_ application: AXUIElement, _ enabled: Bool) {
    let value: CFBoolean = enabled ? kCFBooleanTrue : kCFBooleanFalse
    AXUIElementSetAttributeValue(application, Self.enhancedUserInterfaceAttribute as CFString, value)
  }

  private func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
    var value: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
    guard error == .success else {
      return nil
    }
    return value
  }

  private func element(_ parent: AXUIElement, _ attribute: String) -> AXUIElement? {
    guard let raw = copy(parent, attribute) else {
      return nil
    }
    return Self.asElement(raw)
  }

  private func set(_ element: AXUIElement, _ attribute: String, value: AXValue?) throws {
    guard let value else {
      throw WindowManagerError.attributeFailed(.failure)
    }
    let error = AXUIElementSetAttributeValue(element, attribute as CFString, value)
    guard error == .success else {
      throw WindowManagerError.attributeFailed(error)
    }
  }

  private static func asElement(_ raw: AnyObject) -> AXUIElement? {
    guard CFGetTypeID(raw) == AXUIElementGetTypeID() else {
      return nil
    }
    return unsafeDowncast(raw, to: AXUIElement.self)
  }

  private static func read(_ raw: CFTypeRef, _ type: AXValueType, into result: inout some Any) -> Bool {
    guard CFGetTypeID(raw) == AXValueGetTypeID() else {
      return false
    }
    let value = unsafeDowncast(raw, to: AXValue.self)
    guard AXValueGetType(value) == type else {
      return false
    }
    return AXValueGetValue(value, type, &result)
  }
}

/// Identity of a window for the restore history. `AXUIElement` references to the same window compare equal.
private struct WindowKey: Equatable {
  let element: AXUIElement

  static func == (lhs: WindowKey, rhs: WindowKey) -> Bool {
    CFEqual(lhs.element, rhs.element)
  }
}
