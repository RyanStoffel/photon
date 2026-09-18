import AppKit

extension NSToolbarItem.Identifier {
  static let notesCommandPalette = NSToolbarItem.Identifier("photon.notes.commands")
  static let notesBrowse = NSToolbarItem.Identifier("photon.notes.browse")
  static let notesNew = NSToolbarItem.Identifier("photon.notes.new")
}

extension NotesWindow: NSToolbarDelegate {
  func configureToolbar() {
    let toolbar = NSToolbar(identifier: "photon.notes.toolbar")
    toolbar.delegate = self
    toolbar.displayMode = .iconOnly
    toolbar.allowsUserCustomization = false
    panel.toolbar = toolbar
  }

  func toolbarDefaultItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
    [.flexibleSpace, .notesCommandPalette, .notesBrowse, .notesNew]
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
    case .notesCommandPalette:
      makeItem(
        identifier,
        symbol: "command",
        label: "Commands",
        action: #selector(showCommandsFromToolbar),
        tooltip: "Search for actions (⌘K)"
      )
    case .notesBrowse:
      makeItem(
        identifier,
        symbol: "list.bullet.rectangle",
        label: "Browse Notes",
        action: #selector(showSwitcherFromToolbar),
        tooltip: "Browse notes (⌘P)"
      )
    case .notesNew:
      makeItem(
        identifier,
        symbol: "plus",
        label: "New Note",
        action: #selector(newNoteFromToolbar),
        tooltip: "New note (⌘N)"
      )
    default:
      nil
    }
  }

  private func makeItem(
    _ identifier: NSToolbarItem.Identifier,
    symbol: String,
    label: String,
    action: Selector,
    tooltip: String
  ) -> NSToolbarItem {
    let item = NSToolbarItem(itemIdentifier: identifier)
    item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
    item.label = label
    item.paletteLabel = label
    item.isBordered = true
    item.target = self
    item.action = action
    item.toolTip = tooltip
    return item
  }

  @objc
  private func showCommandsFromToolbar(_: Any?) {
    presentActions()
  }

  @objc
  private func showSwitcherFromToolbar(_: Any?) {
    presentSwitcher()
  }

  @objc
  private func newNoteFromToolbar(_: Any?) {
    controller.createNote()
  }
}
