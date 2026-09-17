import Foundation

/// Roots for the bounded filesystem fallback. Spotlight can search `$HOME`
/// without extra grants; this walk only covers folders Photon may read.
public enum FileSearchFallbackRoots: Sendable {
  public static let standardFolderNames = ["Documents", "Desktop", "Downloads"]

  /// Security-scoped grants first, then readable standard user folders when
  /// searching the home scope. Never adds the entire home directory.
  public static func roots(for settings: FileSearchSettings, home: String = NSHomeDirectory()) -> [String] {
    let manager = FileManager.default
    var seen = Set<String>()
    var roots: [String] = []

    func append(_ path: String) {
      let standardized = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.path
      guard manager.fileExists(atPath: standardized),
            manager.isReadableFile(atPath: standardized),
            seen.insert(standardized).inserted
      else {
        return
      }
      roots.append(standardized)
    }

    for folder in settings.grantedFolders {
      append(folder)
    }

    guard settings.scope == .home else {
      return roots
    }

    let includeStandard = ProcessInfo.processInfo.environment["PHOTON_FILE_SEARCH_STANDARD_ROOTS"] != "0"
    guard includeStandard else {
      return roots
    }

    let homeURL = URL(fileURLWithPath: home, isDirectory: true).standardizedFileURL
    for name in standardFolderNames {
      append(homeURL.appendingPathComponent(name, isDirectory: true).path(percentEncoded: false))
    }
    return roots
  }
}
