import Foundation

/// Inline and block markdown edits used by the notes format toolbar and ⌘K actions.
public enum MarkdownFormatStyle: Equatable, Sendable {
  case heading(Int)
  case bold
  case italic
  case strikethrough
  case underline
  case inlineCode
  case link
  case quote
  case bulletList
  case numberedList
  case checklist
}

public struct MarkdownEdit: Equatable, Sendable {
  public let text: String
  public let selection: NSRange

  public init(text: String, selection: NSRange) {
    self.text = text
    self.selection = selection
  }
}

public enum MarkdownFormat {
  /// Applies `style` to `selection` (UTF-16) in `text`. Empty selections insert markers
  /// and place the caret between them, or retarget the current line for block styles.
  public static func apply(_ style: MarkdownFormatStyle, to text: String, selection: NSRange) -> MarkdownEdit {
    let source = text as NSString
    let safe = clamped(selection, in: source)
    if let markers = wrapMarkers(for: style) {
      return wrap(source, selection: safe, left: markers.left, right: markers.right)
    }
    return applyBlock(style, in: source, selection: safe)
  }

  private static func wrapMarkers(for style: MarkdownFormatStyle) -> (left: String, right: String)? {
    switch style {
    case .bold:
      ("**", "**")
    case .italic:
      ("*", "*")
    case .strikethrough:
      ("~~", "~~")
    case .underline:
      ("<u>", "</u>")
    case .inlineCode:
      ("`", "`")
    default:
      nil
    }
  }

  private static func applyBlock(
    _ style: MarkdownFormatStyle,
    in source: NSString,
    selection: NSRange
  ) -> MarkdownEdit {
    switch style {
    case let .heading(level):
      applyHeading(level: max(1, min(level, 6)), in: source, selection: selection)
    case .link:
      applyLink(in: source, selection: selection)
    case .quote:
      prefixLine(in: source, selection: selection, with: "> ")
    case .bulletList:
      prefixLine(in: source, selection: selection, with: "- ")
    case .numberedList:
      prefixLine(in: source, selection: selection, with: "1. ")
    case .checklist:
      prefixLine(in: source, selection: selection, with: "- [ ] ")
    default:
      MarkdownEdit(text: source as String, selection: selection)
    }
  }

  /// Swaps the list item containing `location` with the previous (`delta < 0`) or next item.
  public static func moveListItem(in text: String, at location: Int, by delta: Int) -> MarkdownEdit? {
    let source = text as NSString
    guard delta != 0, source.length > 0 else {
      return nil
    }
    let index = min(max(location, 0), source.length)
    let current = lineRange(at: index, in: source)
    guard isListItem(source.substring(with: current)) else {
      return nil
    }
    let neighbor: NSRange
    if delta < 0 {
      guard current.location > 0 else {
        return nil
      }
      neighbor = lineRange(at: current.location - 1, in: source)
    } else {
      let nextStart = current.upperBound
      guard nextStart < source.length else {
        return nil
      }
      neighbor = lineRange(at: nextStart, in: source)
    }
    guard isListItem(source.substring(with: neighbor)) else {
      return nil
    }
    let first = current.location < neighbor.location ? current : neighbor
    let second = current.location < neighbor.location ? neighbor : current
    let firstText = source.substring(with: first)
    let secondText = source.substring(with: second)
    let combined = NSMutableString(string: text)
    combined.replaceCharacters(in: second, with: firstText)
    combined.replaceCharacters(in: first, with: secondText)
    let newSelection: NSRange
    if delta < 0 {
      newSelection = first
    } else {
      let offset = (secondText as NSString).length
      newSelection = NSRange(location: first.location + offset, length: 0)
    }
    return MarkdownEdit(text: combined as String, selection: newSelection)
  }

  private static func wrap(_ source: NSString, selection: NSRange, left: String, right: String) -> MarkdownEdit {
    if selection.length > 0 {
      let inner = source.substring(with: selection)
      let replacement = left + inner + right
      let result = source.replacingCharacters(in: selection, with: replacement)
      let location = selection.location + (left as NSString).length
      let innerLength = (inner as NSString).length
      return MarkdownEdit(text: result, selection: NSRange(location: location, length: innerLength))
    }
    let result = source.replacingCharacters(in: selection, with: left + right)
    return MarkdownEdit(
      text: result,
      selection: NSRange(location: selection.location + (left as NSString).length, length: 0)
    )
  }

  private static func applyLink(in source: NSString, selection: NSRange) -> MarkdownEdit {
    let inner = selection.length > 0 ? source.substring(with: selection) : "title"
    let replacement = "[\(inner)](url)"
    let result = source.replacingCharacters(in: selection, with: replacement)
    let urlStart = selection.location + (inner as NSString).length + 3
    return MarkdownEdit(text: result, selection: NSRange(location: urlStart, length: 3))
  }

  private static func applyHeading(level: Int, in source: NSString, selection: NSRange) -> MarkdownEdit {
    let line = lineRange(at: selection.location, in: source)
    var content = source.substring(with: line)
    content = content.replacingOccurrences(of: "^#{1,6}[ \\t]*", with: "", options: .regularExpression)
    let marker = String(repeating: "#", count: level) + " "
    let replacement = marker + content
    let result = source.replacingCharacters(in: line, with: replacement)
    let caret = line.location + (replacement as NSString).length
    return MarkdownEdit(text: result, selection: NSRange(location: caret, length: 0))
  }

  private static func prefixLine(in source: NSString, selection: NSRange, with prefix: String) -> MarkdownEdit {
    let line = lineRange(at: selection.location, in: source)
    let content = source.substring(with: line)
    if content.hasPrefix(prefix) {
      return MarkdownEdit(text: source as String, selection: selection)
    }
    let replacement = prefix + content
    let result = source.replacingCharacters(in: line, with: replacement)
    let caret = selection.location + (prefix as NSString).length
    return MarkdownEdit(text: result, selection: NSRange(location: caret, length: selection.length))
  }

  private static func lineRange(at location: Int, in source: NSString) -> NSRange {
    var start = 0
    var end = 0
    var contentsEnd = 0
    source.getLineStart(
      &start,
      end: &end,
      contentsEnd: &contentsEnd,
      for: NSRange(location: min(location, source.length), length: 0)
    )
    return NSRange(location: start, length: contentsEnd - start)
  }

  private static func isListItem(_ line: String) -> Bool {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
      return true
    }
    guard let dot = trimmed.firstIndex(where: { $0 == "." || $0 == ")" }) else {
      return false
    }
    let number = trimmed[..<dot]
    return !number.isEmpty && number.allSatisfy(\.isNumber)
  }

  private static func clamped(_ range: NSRange, in source: NSString) -> NSRange {
    let location = min(max(range.location, 0), source.length)
    let length = min(max(range.length, 0), source.length - location)
    return NSRange(location: location, length: length)
  }
}
