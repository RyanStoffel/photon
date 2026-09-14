import AppKit

extension NSToolbarItem.Identifier {
  static let newNote = NSToolbarItem.Identifier("photon.notes.new")
  static let noteActions = NSToolbarItem.Identifier("photon.notes.actions")
}

// MARK: - Toolbar

/// Unified toolbar laid out like Notes: the standard sidebar toggle and "New Note" over the sidebar,
/// a tracking separator on the sidebar's edge, then the window title and the actions menu.
extension NotesWindow: NSToolbarDelegate {
  func configureToolbar() {
    let toolbar = NSToolbar(identifier: "photon.notes.toolbar")
    toolbar.delegate = self
    toolbar.displayMode = .iconOnly
    toolbar.allowsUserCustomization = false
    panel.toolbar = toolbar
  }

  func toolbarDefaultItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
    [.toggleSidebar, .newNote, .sidebarTrackingSeparator, .flexibleSpace, .noteActions]
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
    case .toggleSidebar:
      // AppKit normally supplies the standard item; this is the equivalent if it asks.
      let item = makeItem(
        identifier,
        symbol: "sidebar.left",
        label: "Toggle Sidebar",
        action: #selector(NSSplitViewController.toggleSidebar(_:))
      )
      item.target = nil
      item.toolTip = "Hide or show the sidebar (⌃⌘S)"
      return item
    case .sidebarTrackingSeparator:
      return NSTrackingSeparatorToolbarItem(
        identifier: identifier,
        splitView: splitViewController.splitView,
        dividerIndex: 0
      )
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
    let float = addMenuItem(to: menu, title: "Float on Top", action: #selector(toggleFloatOnTop))
    float.state = controller.preferences.floatsAboveOtherWindows ? .on : .off
    floatOnTopItem = float
    menu.addItem(.separator())
    addMenuItem(to: menu, title: "Reveal in Finder", action: #selector(revealInFinder))
    menu.addItem(.separator())
    addMenuItem(to: menu, title: "Delete Note…", action: #selector(deleteNote))
    return menu
  }

  @discardableResult
  private func addMenuItem(to menu: NSMenu, title: String, action: Selector) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
    item.target = self
    menu.addItem(item)
    return item
  }

  /// Fallback target for the standard `toggleSidebar:` action when nothing inside the split view
  /// is the first responder (the window delegate sits in the action chain after the window).
  @objc
  func toggleSidebar(_: Any?) {
    toggleSidebarVisibility()
  }

  @objc
  private func newNoteFromToolbar(_: Any?) {
    controller.createNote()
  }

  @objc
  private func toggleFloatOnTop(_: Any?) {
    controller.setFloatsAboveOtherWindows(!controller.preferences.floatsAboveOtherWindows)
  }

  @objc
  private func revealInFinder(_: Any?) {
    controller.revealInFinder()
  }

  @objc
  private func deleteNote(_: Any?) {
    controller.deleteCurrentNote()
  }
}
