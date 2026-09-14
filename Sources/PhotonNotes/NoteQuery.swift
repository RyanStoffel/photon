import Foundation

/// Interprets launcher input for the notes provider.
///
/// `note`, `notes`, `n <text>`, `note <text>`, and `notes <text>` list notes (optionally filtered).
/// Anything else only matches the fixed "Notes" and "New Note" commands through the registry.
public enum NoteQuery: Equatable, Sendable {
  case unrelated
  case list(filter: String)

  public static let prefixes = ["notes", "note", "n"]

  public static func parse(_ raw: String) -> NoteQuery {
    let query = raw.lowercased().drop(while: \.isWhitespace)
    for prefix in prefixes {
      if query == prefix, prefix != "n" {
        return .list(filter: "")
      }
      if query.hasPrefix(prefix), query.dropFirst(prefix.count).first?.isWhitespace == true {
        let remainder = query.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
        return .list(filter: remainder)
      }
    }
    return .unrelated
  }

  /// Keywords that let the registry's full-query match succeed for a listed note title.
  public static func keywords(forTitle title: String) -> [String] {
    prefixes.map { "\($0) \(title)" }
  }
}
