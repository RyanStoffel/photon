import AppKit
import ApplicationServices

/// Accessibility (and Input Monitoring) status for the event tap and window management.
public enum AccessibilityPermission {
  public static var isTrusted: Bool {
    AXIsProcessTrusted()
  }

  /// Value of `kAXTrustedCheckOptionPrompt`; the imported global is a `var`, which Swift 6 rejects.
  private static let promptOptionKey = "AXTrustedCheckOptionPrompt"

  /// Asks macOS to show its own "grant access" dialog once, then returns the current state.
  @discardableResult
  public static func requestTrust() -> Bool {
    AXIsProcessTrustedWithOptions([promptOptionKey: true] as CFDictionary)
  }

  /// Input Monitoring. Accessibility alone is enough for Photon's tap, so this is informational.
  public static var hasInputMonitoring: Bool {
    CGPreflightListenEventAccess()
  }

  public static func openAccessibilitySettings() {
    open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
  }

  public static func openInputMonitoringSettings() {
    open("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
  }

  private static func open(_ string: String) {
    if let url = URL(string: string) {
      NSWorkspace.shared.open(url)
    }
  }
}
