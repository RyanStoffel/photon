import Foundation

/// Roots for the bounded filesystem fallback. Spotlight can search `$HOME`
/// without extra grants; this walk only covers folders Photon already has
/// security-scoped access to. Ungranted Documents / Desktop / Downloads are
/// never probed, because `isReadableFile` would fire TCC from the launcher.
public enum FileSearchFallbackRoots: Sendable {
  public static let standardFolderNames = ["Documents", "Desktop", "Downloads"]

  /// Folders the Files UI may offer as sequential NSOpenPanel starting points.
  public static func suggestedGrantFolders(home: String = NSHomeDirectory()) -> [URL] {
    let homeURL = URL(fileURLWithPath: home, isDirectory: true).standardizedFileURL
    return standardFolderNames.map { homeURL.appendingPathComponent($0, isDirectory: true) }
  }

  /// Security-scoped grants only. Never adds the entire home directory or
  /// standard user folders that have not been granted.
  public static func roots(for settings: FileSearchSettings, home _: String = NSHomeDirectory()) -> [String] {
    let manager = FileManager.default
    var seen = Set<String>()
    var roots: [String] = []

    for folder in settings.grantedFolders {
      let standardized = URL(fileURLWithPath: folder, isDirectory: true).standardizedFileURL.path
      guard manager.fileExists(atPath: standardized), seen.insert(standardized).inserted else {
        continue
      }
      roots.append(standardized)
    }
    return roots
  }
}
