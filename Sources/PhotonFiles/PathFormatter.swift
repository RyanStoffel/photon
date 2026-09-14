import Foundation

/// Path display helpers: `~` abbreviation and component-aware middle truncation.
public enum PathFormatter: Sendable {
  public static let ellipsis = "\u{2026}"

  public static func abbreviatingHome(_ path: String, home: String = NSHomeDirectory()) -> String {
    let root = home.hasSuffix("/") ? String(home.dropLast()) : home
    guard !root.isEmpty else {
      return path
    }
    if path == root {
      return "~"
    }
    if path.hasPrefix(root + "/") {
      return "~" + path.dropFirst(root.count)
    }
    return path
  }

  /// Shortens a path to at most `maxLength` characters by dropping middle
  /// components first, so the root and the trailing components survive.
  /// Falls back to character-level middle truncation for a single long component.
  public static func middleTruncated(_ path: String, maxLength: Int) -> String {
    guard maxLength > 0, path.count > maxLength else {
      return path
    }
    guard maxLength > 2 else {
      return String(path.prefix(maxLength))
    }

    let absolute = path.hasPrefix("/")
    let components = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    if components.count >= 3 {
      let head = (absolute ? "/" : "") + components[0]
      var tailCount = 1
      var candidate = assemble(head: head, tail: Array(components.suffix(tailCount)))
      if candidate.count <= maxLength {
        while tailCount < components.count - 1 {
          let next = assemble(head: head, tail: Array(components.suffix(tailCount + 1)))
          if next.count > maxLength {
            break
          }
          candidate = next
          tailCount += 1
        }
        return candidate
      }
    }
    return truncateCharacters(path, maxLength: maxLength)
  }

  /// Parent folder of `path`, home-abbreviated and middle-truncated. Suitable for a result subtitle.
  public static func parentDisplay(
    for path: String,
    maxLength: Int = 60,
    home: String = NSHomeDirectory()
  ) -> String {
    let parent = (path as NSString).deletingLastPathComponent
    let abbreviated = abbreviatingHome(parent.isEmpty ? "/" : parent, home: home)
    return middleTruncated(abbreviated, maxLength: maxLength)
  }

  private static func assemble(head: String, tail: [String]) -> String {
    head + "/" + ellipsis + "/" + tail.joined(separator: "/")
  }

  private static func truncateCharacters(_ text: String, maxLength: Int) -> String {
    let keep = maxLength - 1
    let headCount = keep / 2
    let tailCount = keep - headCount
    return String(text.prefix(headCount)) + ellipsis + String(text.suffix(tailCount))
  }
}
