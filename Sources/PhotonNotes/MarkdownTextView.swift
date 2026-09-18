import AppKit

/// Plain markdown editor. Toggles checkboxes on click, continues lists on Return, pastes plain text,
/// and draws a placeholder while empty. Styling is applied by the owner through the text storage.
@MainActor
final class MarkdownTextView: NSTextView {
    textView.placeholder = "Start writing…"

  override func mouseDown(with event: NSEvent) {
    let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    if event.clickCount == 1, modifiers.isEmpty, toggleCheckbox(at: event.locationInWindow) {
      return
    }
    super.mouseDown(with: event)
  }

  override func insertNewline(_ sender: Any?) {
    let selection = selectedRange()
    guard selection.length == 0, !hasMarkedText(),
          let continuation = MarkdownList.continuation(at: selection.location, in: string)
    else {
      super.insertNewline(sender)
      return
    }
    switch continuation {
    case let .insert(text):
      insertText(text, replacementRange: selection)
    case let .terminate(range):
      insertText("", replacementRange: range)
    }
  }

  override func paste(_ sender: Any?) {
    pasteAsPlainText(sender)
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    guard string.isEmpty, !hasMarkedText(), let font else {
      return
    }
    let attributes: [NSAttributedString.Key: Any] = [
      .font: font,
      .foregroundColor: NSColor.placeholderTextColor
    ]
    let padding = textContainer?.lineFragmentPadding ?? 0
    let origin = NSPoint(x: textContainerInset.width + padding, y: textContainerInset.height)
    (placeholder as NSString).draw(at: origin, withAttributes: attributes)
  }

  private func toggleCheckbox(at locationInWindow: NSPoint) -> Bool {
    let point = convert(locationInWindow, from: nil)
    let index = characterIndexForInsertion(at: point)
    guard let toggle = MarkdownCheckbox.toggle(in: string, at: index) else {
      return false
    }
    let selection = selectedRange()
    insertText(toggle.replacement, replacementRange: toggle.range)
    if selection.upperBound <= (string as NSString).length {
      setSelectedRange(selection)
    }
    return true
  }
}
