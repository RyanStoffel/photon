import AppKit
import SwiftUI

/// The floating notes panel: a collapsible sidebar listing every note beside the markdown editor,
/// under a unified toolbar. Built on `NSSplitViewController` so the sidebar gets the system material,
/// the standard toggle, and the full-height layout.
@MainActor
final class NotesWindow: NSObject {
  static let frameAutosaveName = "PhotonNotesWindow.sidebar"
  static let sidebarWidthKey = "PhotonNotesSidebarWidth"
  static let sidebarCollapsedKey = "PhotonNotesSidebarCollapsed"
  static let defaultSize = NSSize(width: 720, height: 480)
  static let minimumSize = NSSize(width: 420, height: 260)
  static let defaultSidebarWidth: CGFloat = 220
  static let sidebarWidthRange: ClosedRange<CGFloat> = 180 ... 340
  static let minimumEditorWidth: CGFloat = 240

  unowned let controller: NotesController
  let panel: NotesPanel
  let textView: MarkdownTextView
  let scrollView: NSScrollView
  let splitViewController = NSSplitViewController()
  let sidebarItem: NSSplitViewItem
  let sidebarController: NSHostingController<NoteSidebarView>
  let sidebarModel: NoteSidebarModel
  let defaults = UserDefaults.standard
  weak var floatOnTopItem: NSMenuItem?

  private(set) var styler: MarkdownTextStyler
  var editorWasEmpty = true

  init(controller: NotesController) {
    self.controller = controller
    styler = MarkdownTextStyler(baseSize: CGFloat(controller.preferences.fontSize))
    panel = NotesPanel(
      contentRect: NSRect(origin: .zero, size: Self.defaultSize),
      styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    let editor = Self.makeEditor(size: Self.defaultSize)
    scrollView = editor.scrollView
    textView = editor.textView
    let model = NoteSidebarModel()
    let hosting = NSHostingController(rootView: NoteSidebarView(model: model))
    sidebarModel = model
    sidebarController = hosting
    sidebarItem = NSSplitViewItem(sidebarWithViewController: hosting)
    super.init()
    configureSplitView()
    configurePanel()
    configureEditor()
    configureToolbar()
    configureSidebar()
  }

  var isVisible: Bool {
    panel.isVisible
  }

  var isKey: Bool {
    panel.isKeyWindow
  }

  func show(focus: Bool) {
    panel.orderFrontRegardless()
    if focus {
      panel.makeKey()
      panel.makeFirstResponder(textView)
    }
  }

  func hide() {
    panel.orderOut(nil)
  }

  func display(_ note: Note, cursorAtEnd: Bool) {
    textView.undoManager?.removeAllActions()
    textView.string = note.content
    restyleWholeDocument()
    updateTitle(note.title)
    let length = (note.content as NSString).length
    textView.setSelectedRange(NSRange(location: cursorAtEnd ? length : 0, length: 0))
    if cursorAtEnd {
      textView.scrollRangeToVisible(textView.selectedRange())
    } else {
      textView.scrollToBeginningOfDocument(nil)
    }
    editorWasEmpty = note.content.isEmpty
    textView.needsDisplay = true
    notesDidChange()
  }

  func focusEditor(atEnd: Bool) {
    panel.makeFirstResponder(textView)
    if atEnd {
      let length = (textView.string as NSString).length
      textView.setSelectedRange(NSRange(location: length, length: 0))
    }
  }

  func updateTitle(_ title: String) {
    panel.title = title
  }

  /// Refreshes the sidebar rows and selection from the controller.
  func notesDidChange() {
    sidebarModel.update(notes: controller.orderedNotes(), selectedID: controller.currentNoteID)
  }

  func apply(_ preferences: NotesPreferences) {
    panel.isFloatingPanel = preferences.floatsAboveOtherWindows
    panel.level = preferences.floatsAboveOtherWindows ? .floating : .normal
    floatOnTopItem?.state = preferences.floatsAboveOtherWindows ? .on : .off
    let size = CGFloat(preferences.fontSize)
    if styler.baseSize != size {
      styler = MarkdownTextStyler(baseSize: size)
      textView.font = styler.baseFont
      textView.typingAttributes = styler.baseAttributes
      restyleWholeDocument()
    }
  }

  func confirmDelete(of title: String) async -> Bool {
    let alert = NSAlert()
    alert.messageText = "Delete “\(title)”?"
    alert.informativeText = "The note will be moved to the Trash."
    alert.alertStyle = .warning
    alert.addButton(withTitle: "Delete").hasDestructiveAction = true
    alert.addButton(withTitle: "Cancel")
    let response = await alert.beginSheetModal(for: panel)
    return response == .alertFirstButtonReturn
  }

  // MARK: Setup

  private func configureSplitView() {
    sidebarItem.minimumThickness = Self.sidebarWidthRange.lowerBound
    sidebarItem.maximumThickness = Self.sidebarWidthRange.upperBound
    sidebarItem.canCollapse = true
    sidebarItem.allowsFullHeightLayout = true
    sidebarController.sizingOptions = []

    let container = NSView()
    container.addSubview(scrollView)
    NSLayoutConstraint.activate([
      scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      scrollView.topAnchor.constraint(equalTo: container.topAnchor),
      scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
    ])
    let editorController = NSViewController()
    editorController.view = container
    let editorItem = NSSplitViewItem(viewController: editorController)
    editorItem.minimumThickness = Self.minimumEditorWidth

    splitViewController.addSplitViewItem(sidebarItem)
    splitViewController.addSplitViewItem(editorItem)
  }

  private func configurePanel() {
    panel.title = "Notes"
    panel.titleVisibility = .visible
    panel.toolbarStyle = .unified
    panel.hidesOnDeactivate = false
    panel.becomesKeyOnlyIfNeeded = false
    panel.isReleasedWhenClosed = false
    panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
    panel.minSize = Self.minimumSize
    panel.animationBehavior = .utilityWindow
    panel.tabbingMode = .disallowed
    panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
    panel.standardWindowButton(.zoomButton)?.isHidden = true
    panel.delegate = self
    panel.shortcutHandler = { [weak self] event in
      self?.handleShortcut(event) ?? false
    }
    panel.contentViewController = splitViewController

    if !panel.setFrameUsingName(Self.frameAutosaveName) {
      panel.setContentSize(Self.defaultSize)
      panel.center()
    }
    panel.setFrameAutosaveName(Self.frameAutosaveName)
  }

  private func configureEditor() {
    textView.delegate = self
    textView.textStorage?.delegate = self
    textView.font = styler.baseFont
    textView.typingAttributes = styler.baseAttributes
  }

  // MARK: Shortcuts

  private func handleShortcut(_ event: NSEvent) -> Bool {
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    if flags.isEmpty {
      return handleUnmodifiedKey(event)
    }
    if flags == [.command, .control], event.charactersIgnoringModifiers?.lowercased() == "s" {
      toggleSidebarVisibility()
      return true
    }
    guard flags.contains(.command), !flags.contains(.option), !flags.contains(.control),
          let key = event.charactersIgnoringModifiers
    else {
      return false
    }
    return runShortcut(key)
  }

  private func handleUnmodifiedKey(_ event: NSEvent) -> Bool {
    switch event.keyCode {
    case 53:
      return handleEscape()
    case 36, 76:
      // Return in the sidebar list hands focus to the editor, like opening the selected note.
      guard isSidebarFocused else {
        return false
      }
      focusEditor(atEnd: false)
      return true
    default:
      return false
    }
  }

  private func handleEscape() -> Bool {
    if isSidebarFocused {
      focusEditor(atEnd: false)
      return true
    }
    if textView.hasMarkedText() {
      return false
    }
    controller.hide()
    return true
  }

  private func runShortcut(_ key: String) -> Bool {
    switch key {
    case "n":
      controller.createNote()
    case "p":
      toggleSidebarFocus()
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

  private func showFindBar() {
    let sender = NSMenuItem()
    sender.tag = NSTextFinder.Action.showFindInterface.rawValue
    textView.performTextFinderAction(sender)
  }
}

// MARK: - Window delegate

extension NotesWindow: NSWindowDelegate {
  func windowShouldClose(_: NSWindow) -> Bool {
    controller.hide()
    return false
  }

  func windowDidBecomeKey(_: Notification) {
    controller.windowDidBecomeKey()
  }

  func windowDidResignKey(_: Notification) {
    controller.windowDidResignKey()
  }
}
