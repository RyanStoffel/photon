import Foundation

public struct RankedFile: Identifiable, Hashable, Sendable {
  public var id: String {
    file.id
  }

  public let file: FileResult
  public let relevance: Double

  public init(file: FileResult, relevance: Double) {
    self.file = file
    self.relevance = relevance
  }
}

/// Orders Spotlight hits: name relevance first, then last-used date, then
/// modification date, then name. Spotlight already narrowed the set; this
/// only decides what the user sees at the top.
public enum FileRanker: Sendable {
  /// Relevance at or above this is good enough to show inline next to apps.
  public static let strongMatchThreshold = 0.7

  public static func rank(
    _ files: [FileResult],
    query: String,
    excludedFolders: [String] = [],
    includeApplications: Bool = true,
    limit: Int,
    home: String = NSHomeDirectory()
  ) -> [RankedFile] {
    guard limit > 0 else {
      return []
    }
    let terms = SpotlightQueryBuilder.terms(from: query).map(fold)
    let wholeQuery = terms.joined(separator: " ")
    let exclusions = normalizedFolders(excludedFolders, home: home)
    var seen = Set<String>()

    let ranked = files.compactMap { file -> RankedFile? in
      guard seen.insert(file.path).inserted else {
        return nil
      }
      if !includeApplications, file.isApplication {
        return nil
      }
      if isExcluded(file.path, normalizedFolders: exclusions) {
        return nil
      }
      let score = relevance(of: file, foldedTerms: terms, wholeQuery: wholeQuery, home: home)
      guard score > 0 else {
        return nil
      }
      return RankedFile(file: file, relevance: score)
    }
    return Array(ranked.sorted(by: precedes).prefix(limit))
  }

  public static func relevance(of file: FileResult, query: String, home: String = NSHomeDirectory()) -> Double {
    let terms = SpotlightQueryBuilder.terms(from: query).map(fold)
    return relevance(of: file, foldedTerms: terms, wholeQuery: terms.joined(separator: " "), home: home)
  }

  public static func isExcluded(_ path: String, folders: [String], home: String = NSHomeDirectory()) -> Bool {
    isExcluded(path, normalizedFolders: normalizedFolders(folders, home: home))
  }

  // MARK: - Scoring

  static func relevance(of file: FileResult, foldedTerms terms: [String], wholeQuery: String, home: String) -> Double {
    guard !terms.isEmpty else {
      return 0
    }
    let relative = PathFormatter.relativeToHome(file.path, home: home) ?? file.path
    let whole = score(query: wholeQuery, stem: file.stem, fileName: file.fileName, relativePath: relative)
    if terms.count == 1 {
      return whole
    }
    let perTerm = terms.map { term in
      score(query: term, stem: file.stem, fileName: file.fileName, relativePath: relative)
    }
    if perTerm.contains(0) {
      return 0
    }
    let averaged = perTerm.reduce(0, +) / Double(perTerm.count)
    return max(whole * 0.95, averaged)
  }

  private static func score(query: String, stem: String, fileName: String, relativePath: String) -> Double {
    let folded = fold(query)
    guard !folded.isEmpty else {
      return 0
    }
    if fold(stem) == folded {
      return 1
    }
    var weighted = 0.0
    if let stemScore = FileFuzzyMatcher.score(query: query, candidate: stem) {
      weighted = max(weighted, stemScore)
    }
    if let nameScore = FileFuzzyMatcher.score(query: query, candidate: fileName) {
      weighted = max(weighted, nameScore * 0.92)
    }
    if let pathScore = FileFuzzyMatcher.score(query: query, candidate: relativePath) {
      weighted = max(weighted, pathScore * 0.78)
    }
    guard weighted > 0 else {
      return 0
    }
    if fold(stem).hasPrefix(folded) {
      weighted = max(weighted, 0.85)
    }
    if wordStartIndices(in: stem).contains(where: { index in
      let slice = fold(stem).dropFirst(index)
      return slice.hasPrefix(folded)
    }) {
      weighted = max(weighted, 0.7)
    }
    return min(weighted, 1)
  }

  /// Indices where a new word begins: after separators and at camelCase humps.
  /// Computed on the unfolded name because folding discards case.
  static func wordStartIndices(in text: String) -> [Int] {
    let chars = Array(text)
    var starts: [Int] = []
    for index in chars.indices {
      if index == 0 {
        starts.append(0)
        continue
      }
      let previous = chars[index - 1]
      let current = chars[index]
      if !previous.isLetter, !previous.isNumber {
        if current.isLetter || current.isNumber {
          starts.append(index)
        }
      } else if previous.isLowercase, current.isUppercase {
        starts.append(index)
      } else if previous.isLetter, current.isNumber {
        starts.append(index)
      }
    }
    return starts
  }

  static func fold(_ text: String) -> String {
    text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
  }

  // MARK: - Ordering

  static func precedes(_ lhs: RankedFile, _ rhs: RankedFile) -> Bool {
    if lhs.relevance != rhs.relevance {
      return lhs.relevance > rhs.relevance
    }
    if let order = compareDates(lhs.file.lastUsed, rhs.file.lastUsed) {
      return order
    }
    if let order = compareDates(lhs.file.modified, rhs.file.modified) {
      return order
    }
    let lhsName = lhs.file.displayName.lowercased()
    let rhsName = rhs.file.displayName.lowercased()
    if lhsName != rhsName {
      return lhsName < rhsName
    }
    return lhs.file.path.count < rhs.file.path.count
  }

  /// Newer first, missing dates last. `nil` means the pair is tied.
  private static func compareDates(_ lhs: Date?, _ rhs: Date?) -> Bool? {
    switch (lhs, rhs) {
    case let (lhs?, rhs?):
      lhs == rhs ? nil : lhs > rhs
    case (.some, .none):
      true
    case (.none, .some):
      false
    case (.none, .none):
      nil
    }
  }

  // MARK: - Exclusions

  static func normalizedFolders(_ folders: [String], home: String) -> [String] {
    folders.compactMap { folder in
      var path = folder.trimmingCharacters(in: .whitespacesAndNewlines)
      if path == "~" {
        path = home
      } else if path.hasPrefix("~/") {
        path = home + path.dropFirst(1)
      }
      while path.count > 1, path.hasSuffix("/") {
        path.removeLast()
      }
      return path.isEmpty ? nil : path
    }
  }

  private static func isExcluded(_ path: String, normalizedFolders folders: [String]) -> Bool {
    folders.contains { folder in
      folder == "/" || path == folder || path.hasPrefix(folder + "/")
    }
  }
}
