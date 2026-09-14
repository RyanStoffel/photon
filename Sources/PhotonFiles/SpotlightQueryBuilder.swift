import Foundation

/// Builds raw Spotlight query strings (`NSPredicate(fromMetadataQueryString:)`).
///
/// Every whitespace-separated term must match. Terms of three or more
/// characters match anywhere in the display name or file name; shorter terms
/// only match at the start of a word so single letters do not flood the
/// result set. Content matching is opt-in and word-prefix based, which is
/// what Spotlight's own UI does.
public enum SpotlightQueryBuilder: Sendable {
  public static let substringMinimumLength = 3

  public static func terms(from query: String) -> [String] {
    var seen = Set<String>()
    var terms: [String] = []
    var current = ""

    func flush() {
      guard !current.isEmpty else {
        return
      }
      if seen.insert(current.lowercased()).inserted {
        terms.append(current)
      }
      current = ""
    }

    for scalar in query.unicodeScalars {
      if CharacterSet.alphanumerics.contains(scalar) {
        current.append(Character(scalar))
      } else {
        flush()
      }
    }
    flush()
    return terms
  }

  /// Escapes a term for use inside a double-quoted Spotlight string literal.
  public static func escape(_ term: String) -> String {
    var out = ""
    out.reserveCapacity(term.count + 2)
    for char in term {
      switch char {
      case "\\", "\"", "*", "?":
        out.append("\\")
        out.append(char)
      default:
        out.append(char)
      }
    }
    return out
  }

  /// Returns `nil` when the query has no searchable terms.
  public static func queryString(for query: String, searchContents: Bool) -> String? {
    let terms = terms(from: query)
    guard !terms.isEmpty else {
      return nil
    }
    let clauses = terms.map { clause(for: $0, searchContents: searchContents) }
    return clauses.count == 1 ? clauses[0] : clauses.joined(separator: " && ")
  }

  static func clause(for term: String, searchContents: Bool) -> String {
    let escaped = escape(term)
    var parts: [String] = []
    if term.count >= substringMinimumLength {
      let anywhere = "\"*\(escaped)*\"cd"
      parts.append("kMDItemDisplayName == \(anywhere)")
      parts.append("kMDItemFSName == \(anywhere)")
    }
    let prefix = "\"\(escaped)*\"cdw"
    parts.append("kMDItemDisplayName == \(prefix)")
    parts.append("kMDItemFSName == \(prefix)")
    if searchContents {
      parts.append("kMDItemTextContent == \"\(escaped)*\"cdw")
    }
    return "(" + parts.joined(separator: " || ") + ")"
  }
}
