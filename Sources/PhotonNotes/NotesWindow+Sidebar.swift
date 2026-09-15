import AppKit

// MARK: - Sidebar

/// Sidebar focus, the ⌘P behaviour, and remembering the sidebar's width and collapsed state.
extension NotesWindow {
  /// Whether keyboard focus is in the sidebar list rather than the editor.
  var isSidebarFocused: Bool {
    guard let view = panel.firstResponder as? NSView else {
      return false
    }
    return view.isDescendant(of: sidebarController.view)
  }

  func configureSidebar() {
    sidebarModel.onSelect = { [weak self] id in
      self?.controller.sidebarDidSelect(id)
    }
    restoreSidebarState()
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(splitViewDidResize),
      name: NSSplitView.didResizeSubviewsNotification,
      object: splitViewController.splitView
    )
  }

  /// ⌘P moves between the list and the editor; from the editor it also expands a collapsed sidebar.
  func toggleSidebarFocus() {
    if isSidebarFocused {
      focusEditor(atEnd: false)
    } else {
      focusSidebar()
    }
  }

  func focusSidebar() {
    if sidebarItem.isCollapsed {
      sidebarItem.animator().isCollapsed = false
    }
    notesDidChange()
    panel.makeKey()
    if let table = Self.firstTableView(in: sidebarController.view) {
      panel.makeFirstResponder(table)
    }
    sidebarModel.requestFocus()
  }

  func toggleSidebarVisibility() {
    splitViewController.toggleSidebar(nil)
  }

  /// Width first, then collapse: a collapsed sidebar reopens at the width its view last had.
  private func restoreSidebarState() {
    var width = Self.defaultSidebarWidth
    if let saved = defaults.object(forKey: Self.sidebarWidthKey) as? Double {
      width = min(max(CGFloat(saved), Self.sidebarWidthRange.lowerBound), Self.sidebarWidthRange.upperBound)
    }
    splitViewController.view.layoutSubtreeIfNeeded()
    splitViewController.splitView.setPosition(width, ofDividerAt: 0)
    sidebarItem.isCollapsed = defaults.bool(forKey: Self.sidebarCollapsedKey)
  }

  @objc
  private func splitViewDidResize(_: Notification) {
    let collapsed = sidebarItem.isCollapsed
    if collapsed != defaults.bool(forKey: Self.sidebarCollapsedKey) {
      defaults.set(collapsed, forKey: Self.sidebarCollapsedKey)
    }
    guard !collapsed, let width = splitViewController.splitView.arrangedSubviews.first?.frame.width,
          Self.sidebarWidthRange.contains(width)
    else {
      return
    }
    if defaults.object(forKey: Self.sidebarWidthKey) as? Double != Double(width) {
      defaults.set(Double(width), forKey: Self.sidebarWidthKey)
    }
  }

  /// The `NSTableView` behind the SwiftUI list, so AppKit can hand it keyboard focus directly.
  private static func firstTableView(in view: NSView) -> NSTableView? {
    if let table = view as? NSTableView {
      return table
    }
    for subview in view.subviews {
      if let table = firstTableView(in: subview) {
        return table
      }
    }
    return nil
  }
}
