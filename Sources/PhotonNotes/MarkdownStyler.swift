import Foundation

public enum MarkdownSpanKind: Equatable, Sendable {
  case heading(level: Int)
  case headingMarker(level: Int)
  case bold
  case italic
  case boldItalic
  case inlineCode
  case codeFence
  case codeBlock
  case listMarker
  case checkbox(checked: Bool)
  case completedItem
  case syntax
}

/// A styled region of markdown source. Ranges are UTF-16 offsets into the full text.
public struct MarkdownSpan: Equatable, Sendable {
  public let range: NSRange
  public let kind: MarkdownSpanKind

  public init(range: NSRange, kind: MarkdownSpanKind) {
    self.range = range
    self.kind = kind
  }
}

/// Computes styling spans for a subset of markdown. The text itself is never changed.
///
/// Supported: ATX headings, bold / italic / bold-italic, inline code, fenced code, bullet
/// and numbered lists, and task checkboxes. Everything is line-local except fences.
public enum MarkdownStyler {
  public static func spans(in text: String) -> [MarkdownSpan] {
    spans(in: text, range: NSRange(location: 0, length: (text as NSString).length))
  }

  /// Spans for every line that intersects `range`. Fence state starts closed at `range.location`,
  /// so pass the whole text when `requiresFullPass` is true.
  public static func spans(in text: String, range: NSRange) -> [MarkdownSpan] {
    let source = Source(text)
    var result: [MarkdownSpan] = []
    var inFence = false
    var location = range.location
    let end = min(range.upperBound, source.length)
    repeat {
      let (line, lineEnd) = source.line(at: location)
      styleLine(line, in: source, inFence: &inFence, into: &result)
      if lineEnd <= location {
        break
      }
      location = lineEnd
    } while location < end
    return result
  }

  /// Fenced code blocks depend on earlier lines, so a paragraph-only restyle is not safe.
  public static func requiresFullPass(_ text: String) -> Bool {
    text.contains("```") || text.contains("~~~")
  }

  private static let fence = Pattern("^ {0,3}(?:```|~~~)")
  private static let heading = Pattern("^(#{1,6})(?:[ \\t]+|$)")
  private static let listItem = Pattern("^[ \\t]*(?:[-*+]|\\d{1,9}[.)])[ \\t]+")
  private static let checkbox = Pattern("^\\[( |x|X)\\](?:[ \\t]+|$)")
  private static let inlineCode = Pattern("(`+)(.+?)\\1")
  private static let emphasis = Pattern(
    "(\\*\\*\\*|___)(?=\\S)(.+?)(?<=\\S)\\1"
      + "|(\\*\\*|__)(?=\\S)(.+?)(?<=\\S)\\3"
      + "|(?<![*\\w])\\*(?=\\S)([^*]+?)(?<=\\S)\\*(?![*\\w])"
      + "|(?<![_\\w])_(?=\\S)([^_]+?)(?<=\\S)_(?![_\\w])"
  )

  private static func styleLine(
    _ line: NSRange,
    in source: Source,
    inFence: inout Bool,
    into result: inout [MarkdownSpan]
  ) {
    if fence.firstMatch(in: source, range: line) != nil {
      inFence.toggle()
      result.append(MarkdownSpan(range: line, kind: .codeFence))
      return
    }
    if inFence {
      if line.length > 0 {
        result.append(MarkdownSpan(range: line, kind: .codeBlock))
      }
      return
    }
    if let match = heading.firstMatch(in: source, range: line) {
      let level = match.range(at: 1).length
      result.append(MarkdownSpan(range: match.range, kind: .headingMarker(level: level)))
      let content = remainder(of: line, after: match.range)
      if content.length > 0 {
        result.append(MarkdownSpan(range: content, kind: .heading(level: level)))
      }
      styleInline(content, in: source, into: &result)
      return
    }
    var inlineRange = line
    if let marker = listItem.firstMatch(in: source, range: line) {
      result.append(MarkdownSpan(range: marker.range, kind: .listMarker))
      inlineRange = remainder(of: line, after: marker.range)
      if let box = checkbox.firstMatch(in: source, range: inlineRange) {
        let checked = source.substring(box.range(at: 1)).lowercased() == "x"
        let brackets = NSRange(location: box.range.location, length: 3)
        result.append(MarkdownSpan(range: brackets, kind: .checkbox(checked: checked)))
        inlineRange = remainder(of: line, after: box.range)
        if checked, inlineRange.length > 0 {
          result.append(MarkdownSpan(range: inlineRange, kind: .completedItem))
        }
      }
    }
    styleInline(inlineRange, in: source, into: &result)
  }

  private static func styleInline(_ range: NSRange, in source: Source, into result: inout [MarkdownSpan]) {
    guard range.length > 0 else {
      return
    }
    let codeMatches = inlineCode.matches(in: source, range: range)
    let codeRanges = codeMatches.map(\.range)
    let emphasisMatches = emphasis.matches(in: source, range: range)
    for match in emphasisMatches where !codeRanges.contains(where: { overlaps($0, match.range) }) {
      appendEmphasis(match, into: &result)
    }
    for match in codeMatches {
      let ticks = match.range(at: 1).length
      let opening = NSRange(location: match.range.location, length: ticks)
      let closing = NSRange(location: match.range.upperBound - ticks, length: ticks)
      result.append(MarkdownSpan(range: opening, kind: .syntax))
      result.append(MarkdownSpan(range: match.range(at: 2), kind: .inlineCode))
      result.append(MarkdownSpan(range: closing, kind: .syntax))
    }
  }

  private static func appendEmphasis(_ match: NSTextCheckingResult, into result: inout [MarkdownSpan]) {
    let kind: MarkdownSpanKind
    let content: NSRange
    if match.range(at: 2).location != NSNotFound {
      kind = .boldItalic
      content = match.range(at: 2)
    } else if match.range(at: 4).location != NSNotFound {
      kind = .bold
      content = match.range(at: 4)
    } else if match.range(at: 5).location != NSNotFound {
      kind = .italic
      content = match.range(at: 5)
    } else {
      kind = .italic
      content = match.range(at: 6)
    }
    let leading = NSRange(location: match.range.location, length: content.location - match.range.location)
    let trailing = NSRange(location: content.upperBound, length: match.range.upperBound - content.upperBound)
    result.append(MarkdownSpan(range: leading, kind: .syntax))
    result.append(MarkdownSpan(range: content, kind: kind))
    result.append(MarkdownSpan(range: trailing, kind: .syntax))
  }

  private static func remainder(of line: NSRange, after prefix: NSRange) -> NSRange {
    NSRange(location: prefix.upperBound, length: max(0, line.upperBound - prefix.upperBound))
  }

  private static func overlaps(_ lhs: NSRange, _ rhs: NSRange) -> Bool {
    NSIntersectionRange(lhs, rhs).length > 0
  }
}

/// Toggles `[ ]` / `[x]` on the line containing a character index.
public enum MarkdownCheckbox {
  public struct Toggle: Equatable, Sendable {
    public let range: NSRange
    public let replacement: String
  }

  /// Returns the edit that flips the checkbox when `index` is on or directly next to its brackets.
  public static func toggle(in text: String, at index: Int) -> Toggle? {
    let source = Source(text)
    guard index >= 0, index <= source.length else {
      return nil
    }
    let (line, _) = source.line(at: index)
    for span in MarkdownStyler.spans(in: text, range: line) {
      guard case let .checkbox(checked) = span.kind else {
        continue
      }
      if index >= span.range.location, index <= span.range.upperBound {
        return Toggle(range: span.range, replacement: checked ? "[ ]" : "[x]")
      }
    }
    return nil
  }
}

/// Decides what pressing Return at the end of a list item should do.
public enum MarkdownList {
  public enum Continuation: Equatable, Sendable {
    /// Insert a newline followed by the next marker, for example `"- [ ] "` or `"3. "`.
    case insert(String)
    /// The item is empty: remove this range (the bare marker) instead of adding another.
    case terminate(NSRange)
  }

  private static let item = Pattern(
    "^([ \\t]*)(?:([-*+])|(\\d{1,9})([.)]))[ \\t]+(\\[(?: |x|X)\\](?:[ \\t]+|$))?"
  )

  /// Only continues when `index` sits at the end of the line, so splitting text stays a plain newline.
  public static func continuation(at index: Int, in text: String) -> Continuation? {
    let source = Source(text)
    guard index >= 0, index <= source.length else {
      return nil
    }
    let (line, _) = source.line(at: index)
    guard index == line.upperBound, let match = item.firstMatch(in: source, range: line) else {
      return nil
    }
    if match.range.upperBound == line.upperBound {
      return .terminate(line)
    }
    let indent = source.substring(match.range(at: 1))
    let checkbox = match.range(at: 5).location == NSNotFound ? "" : "[ ] "
    if match.range(at: 2).location != NSNotFound {
      return .insert("\n\(indent)\(source.substring(match.range(at: 2))) \(checkbox)")
    }
    let number = (Int(source.substring(match.range(at: 3))) ?? 0) + 1
    let delimiter = source.substring(match.range(at: 4))
    return .insert("\n\(indent)\(number)\(delimiter) \(checkbox)")
  }
}

/// UTF-16 view of the text used by the regex passes.
struct Source {
  let string: String
  let nsString: NSString

  init(_ string: String) {
    self.string = string
    nsString = string as NSString
  }

  var length: Int {
    nsString.length
  }

  func substring(_ range: NSRange) -> String {
    nsString.substring(with: range)
  }

  /// The line containing `location` (without its terminator) and the start of the next line.
  func line(at location: Int) -> (NSRange, Int) {
    var lineStart = 0
    var lineEnd = 0
    var contentsEnd = 0
    nsString.getLineStart(
      &lineStart,
      end: &lineEnd,
      contentsEnd: &contentsEnd,
      for: NSRange(location: min(location, length), length: 0)
    )
    return (NSRange(location: lineStart, length: contentsEnd - lineStart), lineEnd)
  }
}

/// Immutable, thread-safe regex wrapper so patterns can live in static lets.
struct Pattern: @unchecked Sendable {
  private let regex: NSRegularExpression

  init(_ pattern: String) {
    do {
      regex = try NSRegularExpression(pattern: pattern)
    } catch {
      preconditionFailure("Invalid pattern \(pattern): \(error)")
    }
  }

  func firstMatch(in source: Source, range: NSRange) -> NSTextCheckingResult? {
    regex.firstMatch(in: source.string, range: range)
  }

  func matches(in source: Source, range: NSRange) -> [NSTextCheckingResult] {
    regex.matches(in: source.string, range: range)
  }
}
