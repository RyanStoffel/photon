import Foundation

/// Whether a Spotlight path may appear for a given search scope.
public enum FilePathScope: Sendable {
  /// Paths under the user's home directory, plus any configured extra folders.
  public static func isAllowed(_ path: String, scope: FileSearchScope, home: String, extraFolders: [String]) -> Bool {
    switch scope {
    case .computer:
      return true
    case .home:
      let resolved = PathFormatter.resolvingFirmlink(path)
      let normalizedHome = normalizeDirectory(home)
      if resolved == normalizedHome || resolved.hasPrefix(normalizedHome + "/") {
        return true
      }
      let extras = FileRanker.normalizedFolders(extraFolders, home: normalizedHome)
      return extras.contains { folder in
        resolved == folder || resolved.hasPrefix(folder + "/")
      }
    }
  }

  /// System locations that must never appear when scope is home, even if Spotlight returns them.
  /// Firmlink prefixes (`/System/Volumes/Data`) are stripped first so files under `~` survive.
  public static func isBlockedSystemPath(_ path: String, home: String) -> Bool {
    let resolved = PathFormatter.resolvingFirmlink(path)
    let normalizedHome = normalizeDirectory(home)
    if isAllowed(resolved, scope: .home, home: normalizedHome, extraFolders: []) {
      return false
    }
    if resolved.hasPrefix("/System") {
      return true
    }
    if resolved.hasPrefix("/Library/") || resolved == "/Library" {
      return true
    }
    if resolved.hasPrefix("/private") {
      return true
    }
    if resolved.hasPrefix("/usr") || resolved == "/usr" {
      return true
    }
    if resolved.hasPrefix("/bin") || resolved == "/bin" {
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
