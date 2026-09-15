import AppKit
import PhotonClipboard
import PhotonCore

// MARK: Keys

extension LauncherPanelController {
  func startMonitor() {
    stopMonitor()
    panel?.keyDownHandler = { [weak self] event in
      guard let self else {
        return false
      }
      switch model.session {
      case .clipboard:
        return handleClipboardKey(event) == nil
      case .commands:
        return handle(event)
      }
    }
  }

  /// Returns true when the launcher consumed the key event.
  func handle(_ event: NSEvent) -> Bool {
    if let mode = model.activeMode, mode.handle(event) {
      return true
    }
    switch event.keyCode {
    case 53:
      escape()
      return true
    case 51:
      return deleteOnEmptyQuery()
    case 126:
      model.moveSelection(-1)
      return true
    case 125:
      model.moveSelection(1)
      return true
    case 36, 76:
      runSelection()
      return true
    default:
      return false
    }
  }

  /// Escape leaves the active mode first and hides the launcher second.
  func escape() {
    if model.activeMode != nil {
      model.exitMode()
    } else {
      hide()
    }
  }

  /// Backspace on an empty query leaves the active mode, like deleting a token.
  func deleteOnEmptyQuery() -> Bool {
    guard model.activeMode != nil, model.query.isEmpty else {
      return false
    }
    model.exitMode()
    return true
  }

  func runSelection() {
    Task {
      if await model.runSelection() {
        hide()
      }
    }
  }

  /// Clipboard session: the clipboard view model owns navigation and actions.
  /// Esc, or Delete on an empty query, returns to the command list.
  func handleClipboardKey(_ event: NSEvent) -> NSEvent? {
    guard let clipboard = model.clipboard else {
      return handle(event) ? nil : event
    }
    if handleClipboardListNavigation(event, clipboard: clipboard) {
      return nil
    }
    if clipboard.handleKeyDown(event) {
      return nil
    }
    let command = event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command)
    switch event.keyCode {
    case 53:
      model.exitClipboard()
      return nil
    case 51 where !command && model.query.isEmpty:
      model.exitClipboard()
      return nil
    default:
      return event
    }
  }

  /// Down expands the compact clipboard list, then Up/Down (and typical list
  /// keys) move through items. Returning true swallows the event so the search
  /// field cannot steal arrow keys.
  func handleClipboardListNavigation(_ event: NSEvent, clipboard: ClipboardHistoryViewModel) -> Bool {
    if let delta = clipboardListDelta(for: event) {
      model.moveSelection(delta)
      return true
    }
    return handleClipboardListJump(event, clipboard: clipboard)
  }

  func clipboardListDelta(for event: NSEvent) -> Int? {
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    guard !flags.contains(.command), !flags.contains(.option) else {
      return nil
    }
    let control = flags.contains(.control)
    switch event.keyCode {
    case 125:
      return 1
    case 45 where control:
      return 1
    case 126:
      return -1
    case 35 where control:
      return -1
    case 121:
      return LauncherLayout.maxVisibleRows
    case 116:
      return -LauncherLayout.maxVisibleRows
    default:
      return nil
    }
  }

  func handleClipboardListJump(_ event: NSEvent, clipboard: ClipboardHistoryViewModel) -> Bool {
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    guard !flags.contains(.command), !flags.contains(.option) else {
      return false
    }
    switch event.keyCode {
    case 115, 119:
      if !model.clipboardShowsResults, !clipboard.results.isEmpty {
        model.moveSelection(1)
      }
      if event.keyCode == 115 {
        clipboard.selectFirst()
      } else {
        clipboard.selectLast()
      }
      return true
    default:
      return false
    }
  }

  func stopMonitor() {
    panel?.keyDownHandler = nil
  }
}
