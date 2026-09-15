import Foundation

/// A bounded filename walk for files that Spotlight has not indexed yet.
///
/// Only folders explicitly selected through the file-access coordinator are
/// traversed. Spotlight remains available without a grant, but this fallback
/// never probes protected home folders and therefore cannot trigger TCC prompts.
enum FileSystemFallbackSearch: Sendable {
  static let defaultTimeLimit: TimeInterval = 1.5
  static let defaultScanLimit = 50000

  static func paths(
    matching query: String,
    roots: [String],
    home: String,
    resultLimit: Int,
    timeLimit: TimeInterval = defaultTimeLimit,
    scanLimit: Int = defaultScanLimit
  ) -> [String] {
    guard resultLimit > 0, scanLimit > 0 else {
      return []
    }
    let terms = SpotlightQueryBuilder.terms(from: query)
    guard !terms.isEmpty else {
      return []
    }

    let deadline = Date().addingTimeInterval(timeLimit)
    let manager = FileManager.default
    var paths: [String] = []
    var seen = Set<String>()
    var scanned = 0

    for root in normalizedRoots(roots) {
      guard !Task.isCancelled, Date() < deadline, scanned < scanLimit, paths.count < resultLimit else {
        break
      }
      guard let enumerator = manager.enumerator(
        at: URL(fileURLWithPath: root, isDirectory: true),
        includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
        options: [.skipsHiddenFiles, .skipsPackageDescendants],
        errorHandler: { _, _ in true }
      ) else {
        continue
      }

      while let url = enumerator.nextObject() as? URL {
        guard !Task.isCancelled, Date() < deadline, scanned < scanLimit, paths.count < resultLimit else {
          break
        }
        scanned += 1
        if shouldSkip(url, home: home) {
          enumerator.skipDescendants()
          continue
        }
        let candidate = url.lastPathComponent
        let relativePath = PathFormatter.relativeToHome(url.path, home: home) ?? url.path
        if terms.allSatisfy({
          FileFuzzyMatcher.matches(query: $0, candidate: candidate)
            || FileFuzzyMatcher.matches(query: $0, candidate: relativePath)
        }), seen.insert(url.path).inserted {
          paths.append(url.path)
        }
      }
    }
    return paths
  }

  private static func normalizedRoots(_ roots: [String]) -> [String] {
    let manager = FileManager.default
    var seen = Set<String>()
    return roots.map {
      URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL.path
    }.filter {
      manager.fileExists(atPath: $0) && seen.insert($0).inserted
    }
  }

  private static func shouldSkip(_ url: URL, home: String) -> Bool {
    let parent = url.deletingLastPathComponent().standardizedFileURL.path
    let normalizedHome = URL(fileURLWithPath: home, isDirectory: true).standardizedFileURL.path
    guard parent == normalizedHome else {
      return false
    }
    return url.lastPathComponent == "Library"
  }
}
