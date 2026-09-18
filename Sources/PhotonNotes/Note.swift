import Foundation

/// One markdown file on disk. The first non-blank line is the title.
public struct Note: Identifiable, Hashable, Sendable {
  /// File name without extension. Stable for the life of the file.
  public let id: String
  public let url: URL
  public var content: String
  public var modifiedAt: Date

  public init(id: String, url: URL, content: String, modifiedAt: Date) {
    self.id = id
    self.url = url
    self.content = content
    self.modifiedAt = modifiedAt
  }

  public var title: String {
    NoteTitle.extract(from: content)
  }

  public var preview: String {
    NoteTitle.preview(from: content)
  }

  public var isBlank: Bool {
    content.allSatisfy(\.isWhitespace)
  }

  public var characterCount: Int {
    content.count
  }
}

/// Lightweight, launcher-facing view of a note.
public struct NoteSummary: Identifiable, Hashable, Sendable {
  public let id: String
  public let title: String
  public let preview: String
  public let modifiedAt: Date

  public init(_ note: Note) {
    id = note.id
    title = note.title
    preview = note.preview
    modifiedAt = note.modifiedAt
  }
}

/// Derives display strings from raw markdown. Pure string logic; no AppKit.
public enum NoteTitle {
  public static let untitled = "Untitled"
  public static let maxTitleLength = 80
  public static let maxPreviewLength = 120

  /// First non-blank line with heading, list, and checkbox markers removed.
  public static func extract(from content: String) -> String {
    guard let line = nonBlankLines(in: content, limit: 1).first else {
      return untitled
    }
    let cleaned = strip(String(line))
    return cleaned.isEmpty ? untitled : truncate(cleaned, to: maxTitleLength)
  }

  /// First non-blank line after the title line, cleaned the same way.
  public static func preview(from content: String) -> String {
    let lines = nonBlankLines(in: content, limit: 2)
    guard lines.count > 1 else {
      return ""
    }
    return truncate(strip(String(lines[1])), to: maxPreviewLength)
  }

  /// Removes leading markdown block markers and wrapping emphasis.
  static func strip(_ line: String) -> String {
    var text = line.trimmingCharacters(in: .whitespaces)
    text = removingPrefix(matching: "^#{1,6}(?:\\s+|$)", from: text)
    text = removingPrefix(matching: "^(?:[-*+]|\\d{1,3}[.)])(?:\\s+|$)", from: text)
    text = removingPrefix(matching: "^\\[(?: |x|X)\\]\\s*", from: text)
    text = removingPrefix(matching: "^>\\s?", from: text)
    for marker in ["***", "**", "__", "*", "_", "`"] {
      if text.count > marker.count * 2, text.hasPrefix(marker), text.hasSuffix(marker) {
        text = String(text.dropFirst(marker.count).dropLast(marker.count))
        break
      }
    }
    let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    return collapsed.trimmingCharacters(in: .whitespaces)
  }

  private static func nonBlankLines(in content: String, limit: Int) -> [Substring] {
    var found: [Substring] = []
    let lines = content.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
    for line in lines where line.contains(where: { !$0.isWhitespace }) {
      found.append(line)
      if found.count == limit {
        break
      }
    }
    return found
  }

  private static func removingPrefix(matching pattern: String, from text: String) -> String {
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
      return text
    }
    let nsText = text as NSString
    let full = NSRange(location: 0, length: nsText.length)
    guard let match = regex.firstMatch(in: text, range: full) else {
      return text
    }
    return nsText.substring(from: match.range.upperBound)
  }

  private static func truncate(_ text: String, to limit: Int) -> String {
    guard text.count > limit else {
      return text
    }
    return String(text.prefix(limit - 1)).trimmingCharacters(in: .whitespaces) + "…"
  }
}
