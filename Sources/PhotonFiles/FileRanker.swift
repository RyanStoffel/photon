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
      return RankedFile(file: file, relevance: relevance(of: file, foldedTerms: terms, wholeQuery: wholeQuery))
    }
    return Array(ranked.sorted(by: precedes).prefix(limit))
  }

  public static func relevance(of file: FileResult, query: String) -> Double {
    let terms = SpotlightQueryBuilder.terms(from: query).map(fold)
    return relevance(of: file, foldedTerms: terms, wholeQuery: terms.joined(separator: " "))
  }

  public static func isExcluded(_ path: String, folders: [String], home: String = NSHomeDirectory()) -> Bool {
    isExcluded(path, normalizedFolders: normalizedFolders(folders, home: home))
  }

  // MARK: - Scoring

  static func relevance(of file: FileResult, foldedTerms terms: [String], wholeQuery: String) -> Double {
    guard !terms.isEmpty else {
      return 0
    }
    let stem = fold(file.stem)
    if stem == wholeQuery {
      return 1
    }
    let fileName = fold(file.fileName)
    let wordStarts = wordStartIndices(in: file.stem)
    let stemChars = Array(stem)
    let total = terms.reduce(0.0) { partial, term in
      partial + termScore(term, stem: stem, stemChars: stemChars, wordStarts: wordStarts, fileName: fileName)
    }
    return total / Double(terms.count)
  }

  private static func termScore(
    _ term: String,
    stem: String,
    stemChars: [Character],
    wordStarts: [Int],
    fileName: String
  ) -> Double {
    if stem == term {
      return 1
    }
    if stem.hasPrefix(term) {
      return 0.85
    }
    if startsWord(term, stemChars: stemChars, wordStarts: wordStarts) {
      return 0.7
    }
    if stem.contains(term) {
      return 0.55
    }
    if fileName.contains(term) {
      return 0.45
    }
    return 0.2
  }

  private static func startsWord(_ term: String, stemChars: [Character], wordStarts: [Int]) -> Bool {
    let needle = Array(term)
    guard !needle.isEmpty else {
      return false
    }
    for start in wordStarts where start > 0 && start + needle.count <= stemChars.count {
      if Array(stemChars[start ..< start + needle.count]) == needle {
        return true
      }
    }
    return false
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
