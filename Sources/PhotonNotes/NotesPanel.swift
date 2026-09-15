import AppKit

/// Floating, non-activating panel that hosts the editor. Handles window-level shortcuts and, because a
/// menu-bar agent may have no Edit menu, routes the standard editing shortcuts itself.
@MainActor
final class NotesPanel: NSPanel {
  var shortcutHandler: ((NSEvent) -> Bool)?

  override var canBecomeKey: Bool {
    true
  }

  override var canBecomeMain: Bool {
    false
  }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if let shortcutHandler, shortcutHandler(event) {
      return true
    }
    if super.performKeyEquivalent(with: event) {
      return true
    }
    return performStandardEditingShortcut(event)
  }

  private func performStandardEditingShortcut(_ event: NSEvent) -> Bool {
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    guard flags.contains(.command), !flags.contains(.option), !flags.contains(.control),
          let key = event.charactersIgnoringModifiers?.lowercased()
    else {
      return false
    }
    let shifted = flags.contains(.shift)
    let action: String? = switch key {
    case "a": shifted ? nil : "selectAll:"
    case "c": shifted ? nil : "copy:"
    case "v": shifted ? nil : "paste:"
    case "x": shifted ? nil : "cut:"
    case "z": shifted ? "redo:" : "undo:"
    default: nil
    }
    guard let action else {
      return false
    }
    return NSApp.sendAction(Selector((action)), to: nil, from: self)
  }
}
