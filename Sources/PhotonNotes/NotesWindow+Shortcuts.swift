import AppKit

extension NotesWindow {
  func handleShortcut(_ event: NSEvent) -> Bool {
    if overlayKind != .none, handleOverlayKey(event) {
      return true
    }
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    if flags.isEmpty {
      return handleUnmodifiedKey(event)
    }
    if flags == [.command], event.charactersIgnoringModifiers?.lowercased() == "k" {
      presentActions()
      return true
    }
    if flags == [.shift, .command], let key = event.charactersIgnoringModifiers?.lowercased() {
      return runShiftCommand(key)
    }
    if flags == [.option, .command] {
      return handleOptionCommand(event)
    }
    guard flags.contains(.command), !flags.contains(.option), !flags.contains(.control),
          let key = event.charactersIgnoringModifiers
    else {
      return false
    }
    return runShortcut(key)
  }

  private func handleOptionCommand(_ event: NSEvent) -> Bool {
    switch event.keyCode {
    case 126:
      moveListItem(by: -1)
      return true
    case 125:
      moveListItem(by: 1)
      return true
    default:
      return false
    }
  }

  private func handleOverlayKey(_ event: NSEvent) -> Bool {
    if event.keyCode == 53 {
      dismissOverlay()
      return true
    }
    switch overlayKind {
    case .switcher:
      return handleListKey(event, move: switcherModel.moveSelection, confirm: switcherModel.openSelection)
    case .actions:
      return handleListKey(event, move: actionsModel.moveSelection, confirm: actionsModel.runSelection)
    case .format, .none:
      return false
    }
  }

  private func handleListKey(
    _ event: NSEvent,
    move: (Int) -> Void,
    confirm: () -> Void
  ) -> Bool {
    switch event.keyCode {
    case 126:
      move(-1)
      return true
    case 125:
      move(1)
      return true
    case 36, 76:
      confirm()
      return true
    default:
      return false
    }
  }

  private func handleUnmodifiedKey(_ event: NSEvent) -> Bool {
    if event.keyCode == 53 {
      if overlayKind != .none {
        dismissOverlay()
        return true
      }
      if textView.hasMarkedText() {
        return false
      }
      controller.hide()
      return true
    }
    return false
  }

  private func runShortcut(_ key: String) -> Bool {
    switch key.lowercased() {
    case "n":
      controller.createNote()
    case "d":
      controller.duplicateCurrentNote()
    case "p":
      presentSwitcher()
    case "w":
      controller.hide()
    case "f":
      showFindBar()
    case "=", "+":
      controller.adjustFontSize(by: 1)
    case "-", "_":
      controller.adjustFontSize(by: -1)
    case "0":
      controller.resetFontSize()
    default:
      return false
    }
    return true
  }

  private func runShiftCommand(_ key: String) -> Bool {
    switch key {
    case "c":
      controller.copyCurrentNote()
    case "d":
      controller.copyDeepLink()
    case "e":
      exportCurrentNote()
    case "f":
      presentFormatBar()
    default:
      return false
    }
    return true
  }

  func runAction(_ id: NoteAction.Kind) {
    dismissOverlay()
    switch id {
    case .newNote:
      controller.createNote()
    case .duplicateNote:
      controller.duplicateCurrentNote()
    case .browseNotes:
      presentSwitcher()
    case .findInNote:
      showFindBar()
    case .copyNote:
      controller.copyCurrentNote()
    case .copyDeepLink:
      controller.copyDeepLink()
    case .exportNote:
      exportCurrentNote()
    case .moveListItemUp:
      moveListItem(by: -1)
    case .moveListItemDown:
      moveListItem(by: 1)
    case .format:
      presentFormatBar()
    }
  }

  func showFindBar() {
    let sender = NSMenuItem()
    sender.tag = NSTextFinder.Action.showFindInterface.rawValue
    textView.performTextFinderAction(sender)
  }

  @objc
  func toggleFormatBar() {
    if overlayKind == .format {
      dismissOverlay()
    } else {
      presentFormatBar()
    }
  }
}
