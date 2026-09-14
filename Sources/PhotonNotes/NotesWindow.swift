import AppKit
import SwiftUI

/// The floating notes panel: toolbar, markdown editor, and the ⌘P switcher popover.
@MainActor
final class NotesWindow: NSObject {
  static let frameAutosaveName = "PhotonNotesWindow"
  static let defaultSize = NSSize(width: 380, height: 460)
  static let minimumSize = NSSize(width: 280, height: 220)

  unowned let controller: NotesController
  let panel: NotesPanel
  let textView: MarkdownTextView
  let scrollView: NSScrollView
  weak var listToolbarItem: NSToolbarItem?

  private(set) var styler: MarkdownTextStyler
  let switcherModel = NoteSwitcherModel()
  var popover: NSPopover?
  var switcherMonitor: Any?
  private var editorWasEmpty = true

  init(controller: NotesController) {
    self.controller = controller
    styler = MarkdownTextStyler(baseSize: CGFloat(controller.preferences.fontSize))
    panel = NotesPanel(
      contentRect: NSRect(origin: .zero, size: Self.defaultSize),
      styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    let editor = Self.makeEditor(size: Self.defaultSize)
    scrollView = editor.scrollView
    textView = editor.textView
    super.init()
    configurePanel()
    configureEditor()
    configureToolbar()
    configureSwitcher()
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
    popover?.close()
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

  func notesDidChange() {
    if popover?.isShown == true {
      switcherModel.update(notes: controller.orderedNotes())
    }
  }

  func apply(_ preferences: NotesPreferences) {
    panel.isFloatingPanel = preferences.floatsAboveOtherWindows
    panel.level = preferences.floatsAboveOtherWindows ? .floating : .normal
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

  private func configurePanel() {
    panel.title = "Notes"
    panel.titleVisibility = .visible
    panel.toolbarStyle = .unifiedCompact
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

    let background = NSVisualEffectView()
    background.material = .underWindowBackground
    background.blendingMode = .behindWindow
    background.state = .followsWindowActiveState
    background.addSubview(scrollView)
    NSLayoutConstraint.activate([
      scrollView.leadingAnchor.constraint(equalTo: background.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: background.trailingAnchor),
      scrollView.topAnchor.constraint(equalTo: background.topAnchor),
      scrollView.bottomAnchor.constraint(equalTo: background.bottomAnchor)
    ])
    panel.contentView = background

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

  private static func makeEditor(size: NSSize) -> (scrollView: NSScrollView, textView: MarkdownTextView) {
    let scrollView = NSScrollView(frame: NSRect(origin: .zero, size: size))
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = false
    scrollView.autohidesScrollers = true
    scrollView.drawsBackground = false
    scrollView.borderType = .noBorder
    scrollView.translatesAutoresizingMaskIntoConstraints = false

    let storage = NSTextStorage()
    let layoutManager = NSLayoutManager()
    storage.addLayoutManager(layoutManager)
    let container = NSTextContainer(size: NSSize(width: size.width, height: CGFloat.greatestFiniteMagnitude))
    container.widthTracksTextView = true
    container.lineFragmentPadding = 4
    layoutManager.addTextContainer(container)

    let textView = MarkdownTextView(
      frame: NSRect(origin: .zero, size: scrollView.contentSize),
      textContainer: container
    )
    textView.minSize = NSSize(width: 0, height: scrollView.contentSize.height)
    textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    textView.isVerticallyResizable = true
    textView.isHorizontallyResizable = false
    textView.autoresizingMask = [.width]
    textView.textContainerInset = NSSize(width: 14, height: 14)
    textView.drawsBackground = false
    textView.isRichText = false
    textView.importsGraphics = false
    textView.allowsUndo = true
    textView.usesFindBar = true
    textView.isIncrementalSearchingEnabled = true
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticDashSubstitutionEnabled = false
    textView.isAutomaticTextReplacementEnabled = false
    textView.isAutomaticSpellingCorrectionEnabled = false
    textView.isContinuousSpellCheckingEnabled = true
    textView.isGrammarCheckingEnabled = false
    textView.smartInsertDeleteEnabled = false
    scrollView.documentView = textView
    return (scrollView, textView)
  }

  // MARK: Styling

  func restyleWholeDocument() {
    guard let storage = textView.textStorage else {
      return
    }
    let text = storage.string
    let range = NSRange(location: 0, length: storage.length)
    styler.apply(MarkdownStyler.spans(in: text, range: range), to: storage, in: range)
  }

  private func restyle(around editedRange: NSRange) {
    guard let storage = textView.textStorage else {
      return
    }
    let text = storage.string
    if MarkdownStyler.requiresFullPass(text) {
      restyleWholeDocument()
      return
    }
    let range = (text as NSString).paragraphRange(for: editedRange)
    styler.apply(MarkdownStyler.spans(in: text, range: range), to: storage, in: range)
  }

  // MARK: Shortcuts

  private func handleShortcut(_ event: NSEvent) -> Bool {
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    if event.keyCode == 53, flags.isEmpty {
      return handleEscape()
    }
    guard flags.contains(.command), !flags.contains(.option), !flags.contains(.control),
          let key = event.charactersIgnoringModifiers
    else {
      return false
    }
    return runShortcut(key)
  }

  private func handleEscape() -> Bool {
    if let popover, popover.isShown {
      popover.close()
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
      toggleSwitcher()
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

// MARK: - Delegates

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

extension NotesWindow: NSTextViewDelegate {
  func textDidChange(_: Notification) {
    let text = textView.string
    if text.isEmpty != editorWasEmpty {
      editorWasEmpty = text.isEmpty
      textView.needsDisplay = true
    }
    controller.editorDidChange(text)
  }
}

extension NotesWindow: NSTextStorageDelegate {
  func textStorage(
    _: NSTextStorage,
    didProcessEditing editedMask: NSTextStorageEditActions,
    range editedRange: NSRange,
    changeInLength _: Int
  ) {
    guard editedMask.contains(.editedCharacters) else {
      return
    }
    restyle(around: editedRange)
  }
}
