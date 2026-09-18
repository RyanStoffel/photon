import AppKit

// MARK: - Editor

/// The editor column: text view construction and the markdown restyling passes.
extension NotesWindow {
  static func makeEditor(size: NSSize) -> (scrollView: NSScrollView, textView: MarkdownTextView) {
    let scrollView = NSScrollView(frame: NSRect(origin: .zero, size: size))
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = false
    scrollView.autohidesScrollers = true
    scrollView.drawsBackground = false
    scrollView.backgroundColor = .clear
    scrollView.borderType = .noBorder
    scrollView.translatesAutoresizingMaskIntoConstraints = false

    let storage = NSTextStorage()
    let layoutManager = NSLayoutManager()
    storage.addLayoutManager(layoutManager)
    let container = NSTextContainer(size: NSSize(width: size.width, height: CGFloat.greatestFiniteMagnitude))
    container.widthTracksTextView = true
    container.lineFragmentPadding = 2
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
    // Roughly the Notes editor margins; the container padding brings the text to 20 pt from the edge.
    textView.textContainerInset = NSSize(
      width: NotesLayout.editorHorizontalInset,
      height: NotesLayout.editorVerticalInset
    )
    textView.drawsBackground = false
    textView.backgroundColor = .clear
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
    styler.apply(spans(in: text, range: range), to: storage, in: range)
  }

  /// Restyles the edited paragraph, or everything when fences or the title line are involved.
  func restyle(around editedRange: NSRange) {
    guard let storage = textView.textStorage else {
      return
    }
    let text = storage.string
    let range = (text as NSString).paragraphRange(for: editedRange)
    if MarkdownStyler.requiresFullPass(text) || MarkdownStyler.editAffectsTitle(range, in: text) {
      restyleWholeDocument()
      return
    }
    styler.apply(spans(in: text, range: range), to: storage, in: range)
  }

  /// Markdown spans plus the title span last, so the title look wins on the first line.
  private func spans(in text: String, range: NSRange) -> [MarkdownSpan] {
    var spans = MarkdownStyler.spans(in: text, range: range)
    if let title = MarkdownStyler.titleSpan(in: text) {
      spans.append(title)
    }
    return spans
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
    updateCharacterCount()
  }
}

extension NotesWindow: NSTextStorageDelegate {
  /// `NSTextStorageDelegate` is nonisolated in the SDK; the storage is only ever edited on the main thread.
  nonisolated func textStorage(
    _: NSTextStorage,
    didProcessEditing editedMask: NSTextStorageEditActions,
    range editedRange: NSRange,
    changeInLength _: Int
  ) {
    guard editedMask.contains(.editedCharacters) else {
      return
    }
    MainActor.assumeIsolated {
      restyle(around: editedRange)
    }
  }
}
