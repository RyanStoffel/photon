import Foundation

/// Whether a Spotlight path may appear for a given search scope.
public enum FilePathScope: Sendable {
  /// Paths under the user's home directory, plus any configured extra folders.
  public static func isAllowed(_ path: String, scope: FileSearchScope, home: String, extraFolders: [String]) -> Bool {
    switch scope {
    case .computer:
      return true
    case .home:
      let normalizedHome = normalizeDirectory(home)
      if path == normalizedHome || path.hasPrefix(normalizedHome + "/") {
        return true
      }
      let extras = FileRanker.normalizedFolders(extraFolders, home: normalizedHome)
      return extras.contains { folder in
        path == folder || path.hasPrefix(folder + "/")
      }
    }
  }

  /// System locations that must never appear when scope is home, even if Spotlight returns them.
  public static func isBlockedSystemPath(_ path: String, home: String) -> Bool {
    let normalizedHome = normalizeDirectory(home)
    if isAllowed(path, scope: .home, home: normalizedHome, extraFolders: []) {
      return false
    }
    if path.hasPrefix("/System") {
      return true
    }
    if path.hasPrefix("/Library/") || path == "/Library" {
      return true
    }
    if path.hasPrefix("/private") {
      return true
    }
    if path.hasPrefix("/usr") || path == "/usr" {
      return true
    }
    if path.hasPrefix("/bin") || path == "/bin" {
      return true
    }
    if path.hasPrefix("/System/Volumes/Data/") {
      let remainder = String(path.dropFirst("/System/Volumes/Data".count))
      if remainder.hasPrefix(normalizedHome) || remainder.hasPrefix(normalizedHome + "/") {
        return false
      }
      return true
    }
    return false
  }

  private static func normalizeDirectory(_ path: String) -> String {
    var trimmed = path
    while trimmed.count > 1, trimmed.hasSuffix("/") {
      trimmed.removeLast()
    }
    return trimmed
  }
}
