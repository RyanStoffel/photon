import AppKit
import SwiftUI

extension NSToolbarItem.Identifier {
  static let notesList = NSToolbarItem.Identifier("photon.notes.list")
  static let newNote = NSToolbarItem.Identifier("photon.notes.new")
  static let noteActions = NSToolbarItem.Identifier("photon.notes.actions")
}

// MARK: - Toolbar

extension NotesWindow: NSToolbarDelegate {
  func configureToolbar() {
    let toolbar = NSToolbar(identifier: "photon.notes.toolbar")
    toolbar.delegate = self
    toolbar.displayMode = .iconOnly
    toolbar.allowsUserCustomization = false
    panel.toolbar = toolbar
  }

  func toolbarDefaultItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
    [.notesList, .flexibleSpace, .newNote, .noteActions]
  }

  func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    toolbarDefaultItemIdentifiers(toolbar)
  }

  func toolbar(
    _: NSToolbar,
    itemForItemIdentifier identifier: NSToolbarItem.Identifier,
    willBeInsertedIntoToolbar _: Bool
  ) -> NSToolbarItem? {
    switch identifier {
    case .notesList:
      let item = makeItem(identifier, symbol: "list.bullet", label: "Notes", action: #selector(showSwitcherFromToolbar))
      item.toolTip = "Switch notes (⌘P)"
      item.isNavigational = true
      listToolbarItem = item
      return item
    case .newNote:
      let item = makeItem(
        identifier,
        symbol: "square.and.pencil",
        label: "New Note",
        action: #selector(newNoteFromToolbar)
      )
      item.toolTip = "New note (⌘N)"
      return item
    case .noteActions:
      let item = NSMenuToolbarItem(itemIdentifier: identifier)
      item.image = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: "More")
      item.label = "More"
      item.paletteLabel = "More"
      item.showsIndicator = false
      item.menu = actionsMenu()
      return item
    default:
      return nil
    }
  }

  private func makeItem(
    _ identifier: NSToolbarItem.Identifier,
    symbol: String,
    label: String,
    action: Selector
  ) -> NSToolbarItem {
    let item = NSToolbarItem(itemIdentifier: identifier)
    item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
    item.label = label
    item.paletteLabel = label
    item.isBordered = true
    item.target = self
    item.action = action
    return item
  }

  private func actionsMenu() -> NSMenu {
    let menu = NSMenu()
    addMenuItem(to: menu, title: "Reveal in Finder", action: #selector(revealInFinder))
    menu.addItem(.separator())
    addMenuItem(to: menu, title: "Bigger Text", action: #selector(increaseTextSize), key: "+")
    addMenuItem(to: menu, title: "Smaller Text", action: #selector(decreaseTextSize), key: "-")
    addMenuItem(to: menu, title: "Reset Text Size", action: #selector(resetTextSize), key: "0")
    menu.addItem(.separator())
    addMenuItem(to: menu, title: "Delete Note…", action: #selector(deleteNote))
    return menu
  }

  private func addMenuItem(to menu: NSMenu, title: String, action: Selector, key: String = "") {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
    item.target = self
    menu.addItem(item)
  }

  @objc
  private func showSwitcherFromToolbar(_: Any?) {
    toggleSwitcher()
  }

  @objc
  private func newNoteFromToolbar(_: Any?) {
    controller.createNote()
  }

  @objc
  private func revealInFinder(_: Any?) {
    controller.revealInFinder()
  }

  @objc
  private func increaseTextSize(_: Any?) {
    controller.adjustFontSize(by: 1)
  }

  @objc
  private func decreaseTextSize(_: Any?) {
    controller.adjustFontSize(by: -1)
  }

  @objc
  private func resetTextSize(_: Any?) {
    controller.resetFontSize()
  }

  @objc
  private func deleteNote(_: Any?) {
    controller.deleteCurrentNote()
  }
}

// MARK: - Switcher popover

extension NotesWindow: NSPopoverDelegate {
  func configureSwitcher() {
    switcherModel.onOpen = { [weak self] id in
      self?.popover?.close()
      self?.controller.switcherDidSelect(id)
    }
    switcherModel.onCreate = { [weak self] title in
      self?.popover?.close()
      self?.controller.createNote(content: "# \(title)\n\n")
    }
  }

  func toggleSwitcher() {
    if let popover, popover.isShown {
      popover.close()
    } else {
      showSwitcher()
    }
  }

  func showSwitcher() {
    controller.flush()
    switcherModel.update(notes: controller.orderedNotes())
    switcherModel.query = ""
    switcherModel.selectedID = controller.currentNoteID
    let popover = popover ?? makePopover()
    self.popover = popover
    if let listToolbarItem {
      popover.show(relativeTo: listToolbarItem)
    } else if let contentView = panel.contentView {
      let anchor = NSRect(x: 12, y: contentView.bounds.maxY - 1, width: 1, height: 1)
      popover.show(relativeTo: anchor, of: contentView, preferredEdge: .maxY)
    }
    installSwitcherMonitor()
  }

  func popoverDidClose(_: Notification) {
    removeSwitcherMonitor()
    if panel.isKeyWindow {
      panel.makeFirstResponder(textView)
    }
  }

  private func makePopover() -> NSPopover {
    let popover = NSPopover()
    popover.behavior = .transient
    popover.animates = true
    popover.delegate = self
    popover.contentViewController = NSHostingController(rootView: NoteSwitcherView(model: switcherModel))
    return popover
  }

  private func installSwitcherMonitor() {
    removeSwitcherMonitor()
    switcherMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self, let popover, popover.isShown else {
        return event
      }
      switch event.keyCode {
      case 125:
        switcherModel.moveSelection(1)
        return nil
      case 126:
        switcherModel.moveSelection(-1)
        return nil
      case 36, 76:
        switcherModel.openSelection()
        return nil
      case 53:
        popover.close()
        return nil
      default:
        return event
      }
    }
  }

  private func removeSwitcherMonitor() {
    if let switcherMonitor {
      NSEvent.removeMonitor(switcherMonitor)
      self.switcherMonitor = nil
    }
  }
}
