#if canImport(AppKit)
import AppKit
import ApplicationServices
import Carbon
import Foundation

/// Writes history items back to the pasteboard and, when Accessibility access
/// is granted, sends Cmd+V to the frontmost app.
public enum ClipboardPaster: Sendable {
  private static let accessibilityPromptKey = "AXTrustedCheckOptionPrompt"
  private static let accessibilitySettingsURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

  /// Whether macOS lets Photon post keyboard events.
  public static var isAccessibilityTrusted: Bool {
    AXIsProcessTrusted()
  }

  /// Shows the system prompt that offers to open Privacy & Security > Accessibility.
  @discardableResult
  public static func requestAccessibility() -> Bool {
    let options: [String: Any] = [accessibilityPromptKey: true]
    return AXIsProcessTrustedWithOptions(options as CFDictionary)
  }

  public static func openAccessibilitySettings() {
    if let url = URL(string: accessibilitySettingsURL) {
      _ = NSWorkspace.shared.open(url)
    }
  }

  /// Replaces the general pasteboard with the item's representations and
  /// returns the resulting change count, so the monitor can ignore the write.
  @discardableResult
  public static func write(_ item: ClipboardItem, payload: ClipboardStore.Payload) -> Int {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()

    switch item.kind {
    case .file:
      let urls = payload.filePaths.map { URL(fileURLWithPath: $0) as NSURL }
      if !urls.isEmpty {
        pasteboard.writeObjects(urls)
      }
    case .text, .link, .image:
      if let text = payload.text {
        pasteboard.setString(text, forType: .string)
        if item.kind == .link {
          pasteboard.setString(text.trimmingCharacters(in: .whitespacesAndNewlines), forType: .URL)
        }
      }
      if let richText = payload.richText {
        pasteboard.setData(richText, forType: .rtf)
      }
      if let png = payload.imagePNG {
        pasteboard.setData(png, forType: .png)
        if let tiff = NSBitmapImageRep(data: png)?.tiffRepresentation {
          pasteboard.setData(tiff, forType: .tiff)
        }
      }
    }
    return pasteboard.changeCount
  }

  /// Posts Cmd+V to the session. Returns `false` when Accessibility is not granted.
  @discardableResult
  public static func sendPasteKeystroke() -> Bool {
    guard isAccessibilityTrusted else {
      return false
    }
    let source = CGEventSource(stateID: .combinedSessionState)
    source?.setLocalEventsFilterDuringSuppressionState(
      [.permitLocalMouseEvents, .permitSystemDefinedEvents],
      state: .eventSuppressionStateSuppressionInterval
    )
    let key = CGKeyCode(kVK_ANSI_V)
    guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
          let keyUp = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
    else {
      return false
    }
    keyDown.flags = .maskCommand
    keyUp.flags = .maskCommand
    keyDown.post(tap: .cgAnnotatedSessionEventTap)
    keyUp.post(tap: .cgAnnotatedSessionEventTap)
    return true
  }
}
#endif
