import AppKit
import UniformTypeIdentifiers

/// The floating notes panel: vibrancy editor, character count, switcher / actions overlays.
@MainActor
final class NotesWindow: NSObject {
  static let frameAutosaveName = "PhotonNotesWindow.v039"
  static let defaultSize = NSSize(width: NotesLayout.panelWidth, height: NotesLayout.defaultHeight)
  static let minimumSize = NSSize(width: NotesLayout.panelWidth, height: NotesLayout.minimumHeight)

  enum OverlayKind: String {
    case none
    case switcher
    case actions
    case format
  }

  unowned let controller: NotesController
  let panel: NotesPanel
  let textView: MarkdownTextView
  let scrollView: NSScrollView
  let switcherModel = NoteSwitcherModel()
  let actionsModel = NoteActionsModel()
  weak var floatOnTopItem: NSMenuItem?

  private(set) var styler: MarkdownTextStyler
  var editorWasEmpty = true
  var overlayKind: OverlayKind = .none
  private let effectView = NSVisualEffectView()
  let overlayContainer = NSView()
  var overlayHosting: NSHostingView<NotesOverlayView>?
  private let footerLabel = NSTextField(labelWithString: NotesLayout.characterCountLabel(0, capitalized: false))
  private let formatButton = NSButton()

  init(controller: NotesController) {
    self.controller = controller
    styler = MarkdownTextStyler(baseSize: CGFloat(controller.preferences.fontSize))
    panel = NotesPanel(
      contentRect: NSRect(origin: .zero, size: Self.defaultSize),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    let editor = Self.makeEditor(size: Self.defaultSize)
    scrollView = editor.scrollView
    textView = editor.textView
    super.init()
    configureContent()
    configurePanel()
    configureEditor()
    configureToolbar()
    configureOverlays()
  }

  var isVisible: Bool {
    panel.isVisible
  }

  var isKey: Bool {
    panel.isKeyWindow
  }

  var overlayName: String {
    overlayKind.rawValue
  }

  func show(focus: Bool) {
    applyFixedWidth(preservingHeight: panel.frame.height)
    panel.orderFrontRegardless()
    if focus {
      panel.makeKey()
      panel.makeFirstResponder(textView)
    }
  }

  func hide() {
    dismissOverlay()
    panel.orderOut(nil)
  }

  func display(_ note: Note, cursorAtEnd: Bool) {
    textView.undoManager?.removeAllActions()
    textView.string = note.content
    restyleWholeDocument()
    updateTitle(note.title)
    updateCharacterCount()
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
    let items = NoteSwitcherItem.items(
      from: controller.orderedNotes(),
      currentID: controller.currentNoteID,
      pinned: controller.pinnedIDs
    )
    switcherModel.update(items: items, selectedID: controller.currentNoteID)
    updateCharacterCount()
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

  func presentSwitcher() {
    showOverlay(.switcher)
  }

  func presentActions() {
    actionsModel.query = ""
    actionsModel.selectedID = NoteAction.catalog.first?.id
    showOverlay(.actions)
  }

  func presentFormatBar() {
    showOverlay(.format)
  }

  func dismissOverlay() {
    showOverlay(.none)
    panel.makeFirstResponder(textView)
  }

  func applyFormat(_ style: MarkdownFormatStyle) {
    let edit = MarkdownFormat.apply(style, to: textView.string, selection: textView.selectedRange())
    replaceEditor(with: edit)
  }

  func moveListItem(by delta: Int) {
    guard let edit = MarkdownFormat.moveListItem(
      in: textView.string,
      at: textView.selectedRange().location,
      by: delta
    ) else {
      return
    }
    replaceEditor(with: edit)
  }

  func exportCurrentNote() {
    guard let note = controller.currentNote else {
      return
    }
    let save = NSSavePanel()
    save.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
    save.nameFieldStringValue = "\(note.title).md"
    save.beginSheetModal(for: panel) { [weak self] response in
      guard response == .OK, let url = save.url else {
        return
      }
      try? (self?.textView.string ?? note.content).write(to: url, atomically: true, encoding: .utf8)
    }
  }

  // MARK: Setup

  private func configureContent() {
    effectView.material = .hudWindow
    effectView.blendingMode = .behindWindow
    effectView.state = .active
    effectView.wantsLayer = true
    effectView.layer?.cornerRadius = NotesLayout.cornerRadius
    effectView.layer?.masksToBounds = true

    scrollView.drawsBackground = false
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    textView.drawsBackground = false
    textView.backgroundColor = .clear

    footerLabel.font = .systemFont(ofSize: 11)
    footerLabel.textColor = .tertiaryLabelColor
    footerLabel.alignment = .center
    footerLabel.translatesAutoresizingMaskIntoConstraints = false

    formatButton.title = "T"
    formatButton.bezelStyle = .inline
    formatButton.isBordered = false
    formatButton.font = .systemFont(ofSize: 12, weight: .semibold)
    formatButton.contentTintColor = .tertiaryLabelColor
    formatButton.target = self
    formatButton.action = #selector(toggleFormatBar)
    formatButton.translatesAutoresizingMaskIntoConstraints = false
    formatButton.toolTip = "Format"

    overlayContainer.translatesAutoresizingMaskIntoConstraints = false
    overlayContainer.isHidden = true

    let root = NSView()
    root.wantsLayer = true
    root.addSubview(effectView)
    effectView.translatesAutoresizingMaskIntoConstraints = false
    root.addSubview(scrollView)
    root.addSubview(footerLabel)
    root.addSubview(formatButton)
    root.addSubview(overlayContainer)
    panel.contentView = root

    NSLayoutConstraint.activate([
      effectView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      effectView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      effectView.topAnchor.constraint(equalTo: root.topAnchor),
      effectView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
      scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      scrollView.topAnchor.constraint(equalTo: root.topAnchor),
      scrollView.bottomAnchor.constraint(equalTo: footerLabel.topAnchor),
      footerLabel.centerXAnchor.constraint(equalTo: root.centerXAnchor),
      footerLabel.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -10),
      footerLabel.heightAnchor.constraint(equalToConstant: 16),
      formatButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
      formatButton.centerYAnchor.constraint(equalTo: footerLabel.centerYAnchor),
      overlayContainer.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      overlayContainer.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      overlayContainer.topAnchor.constraint(equalTo: root.topAnchor),
      overlayContainer.bottomAnchor.constraint(equalTo: root.bottomAnchor),
    ])
  }

  private func configurePanel() {
    panel.title = "Untitled"
    panel.titleVisibility = .visible
    panel.titlebarAppearsTransparent = true
    panel.toolbarStyle = .unifiedCompact
    panel.hidesOnDeactivate = false
    panel.becomesKeyOnlyIfNeeded = false
    panel.isReleasedWhenClosed = false
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
    panel.minSize = Self.minimumSize
    panel.maxSize = NSSize(width: NotesLayout.panelWidth, height: CGFloat.greatestFiniteMagnitude)
    panel.animationBehavior = .utilityWindow
    panel.tabbingMode = .disallowed
    panel.delegate = self
    panel.shortcutHandler = { [weak self] event in
      self?.handleShortcut(event) ?? false
    }

    if !panel.setFrameUsingName(Self.frameAutosaveName) {
      panel.setContentSize(Self.defaultSize)
      panel.center()
    }
    applyFixedWidth(preservingHeight: panel.frame.height)
    panel.setFrameAutosaveName(Self.frameAutosaveName)
  }

  private func configureEditor() {
    textView.delegate = self
    textView.textStorage?.delegate = self
    textView.font = styler.baseFont
    textView.typingAttributes = styler.baseAttributes
    textView.placeholder = "Start writing…"
  }

  private func configureOverlays() {
    switcherModel.onOpen = { [weak self] id in
      self?.controller.openFromSwitcher(id)
      self?.dismissOverlay()
    }
    switcherModel.onPin = { [weak self] id in
      self?.controller.togglePin(id)
      self?.notesDidChange()
    }
    switcherModel.onDelete = { [weak self] id in
      self?.controller.deleteNote(id: id)
    }
    actionsModel.onRun = { [weak self] id in
      self?.runAction(id)
    }
  }

  private func showOverlay(_ kind: OverlayKind) {
    overlayKind = kind
    rebuildOverlay()
    if kind == .none {
      panel.makeFirstResponder(textView)
    }
  }

  private func applyFixedWidth(preservingHeight height: CGFloat) {
    var frame = panel.frame
    frame.size = NotesLayout.constrainedSize(from: CGSize(width: frame.width, height: height))
    panel.setFrame(frame, display: true)
  }

  func updateCharacterCount() {
    footerLabel.stringValue = NotesLayout.characterCountLabel(textView.string.count, capitalized: false)
  }

  private func replaceEditor(with edit: MarkdownEdit) {
    textView.string = edit.text
    textView.setSelectedRange(edit.selection)
    restyleWholeDocument()
    controller.editorDidChange(edit.text)
    updateCharacterCount()
  }

  // MARK: Shortcuts

  private func handleShortcut(_ event: NSEvent) -> Bool {
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
      switch event.keyCode {
      case 126:
        moveListItem(by: -1)
        return true
      case 125:
        moveListItem(by: 1)
        return true
      default:
        break
      }
    }
    guard flags.contains(.command), !flags.contains(.option), !flags.contains(.control),
          let key = event.charactersIgnoringModifiers
    else {
      return false
    }
    return runShortcut(key)
  }

  private func handleOverlayKey(_ event: NSEvent) -> Bool {
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    if event.keyCode == 53 {
      dismissOverlay()
      return true
    }
    if overlayKind == .switcher {
      switch event.keyCode {
      case 126:
        switcherModel.moveSelection(-1)
        return true
      case 125:
        switcherModel.moveSelection(1)
        return true
      case 36, 76:
        switcherModel.openSelection()
        return true
      default:
        return false
      }
    }
    if overlayKind == .actions {
      switch event.keyCode {
      case 126:
        actionsModel.moveSelection(-1)
        return true
      case 125:
        actionsModel.moveSelection(1)
        return true
      case 36, 76:
        actionsModel.runSelection()
        return true
      default:
        return false
      }
    }
    if overlayKind == .format, flags.isEmpty, event.keyCode == 53 {
      dismissOverlay()
      return true
    }
    return false
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

  func runAction(_ id: NoteAction.ID) {
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

  private func showFindBar() {
    let sender = NSMenuItem()
    sender.tag = NSTextFinder.Action.showFindInterface.rawValue
    textView.performTextFinderAction(sender)
  }

  @objc
  private func toggleFormatBar() {
    if overlayKind == .format {
      dismissOverlay()
    } else {
      presentFormatBar()
    }
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

  func windowWillResize(_: NSWindow, to frameSize: NSSize) -> NSSize {
    let constrained = NotesLayout.constrainedSize(from: CGSize(width: frameSize.width, height: frameSize.height))
    return NSSize(width: constrained.width, height: constrained.height)
  }
}
