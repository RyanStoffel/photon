import Foundation

/// Case-insensitive subsequence matcher with a score in `(0, 1]`.
///
/// Returns `nil` when `query` is not a subsequence of `candidate`. An empty
/// query is treated as a match with score `1` so callers can decide whether
/// to show a default list instead.
public enum FuzzyMatcher: Sendable {
  public static func matches(query: String, candidate: String) -> Bool {
    score(query: query, candidate: candidate) != nil
  }

  public static func score(query: String, candidate: String) -> Double? {
    let needle = Array(query.lowercased())
    let hay = Array(candidate.lowercased())
    let original = Array(candidate)

    if needle.isEmpty {
      return 1
    }
    if hay.isEmpty {
      return nil
    }

    var hayIndex = 0
    var consecutive = 0
    var maxConsecutive = 0
    var firstIndex: Int?
    var wordStartHits = 0

    for char in needle {
      var found = false
      while hayIndex < hay.count {
        if hay[hayIndex] == char {
          if firstIndex == nil {
            firstIndex = hayIndex
          }
          if hayIndex == 0 || isWordStart(original, hayIndex) {
            wordStartHits += 1
          }
          consecutive += 1
          maxConsecutive = max(maxConsecutive, consecutive)
          hayIndex += 1
          found = true
          break
        }
        consecutive = 0
        hayIndex += 1
      }
      if !found {
        return nil
      }
    }

    let coverage = Double(needle.count) / Double(hay.count)
    let consecutiveBonus = Double(maxConsecutive) / Double(needle.count)
    let prefixBonus = firstIndex == 0 ? 0.25 : 0
    let wordBonus = Double(wordStartHits) / Double(needle.count) * 0.2
    let exactBonus = query.caseInsensitiveCompare(candidate) == .orderedSame ? 0.35 : 0
    let compactness = 1 - Double((hayIndex - (firstIndex ?? 0)) - needle.count) / Double(max(hay.count, 1))

    let raw =
      0.35 * coverage
        + 0.25 * consecutiveBonus
        + 0.15 * max(compactness, 0)
        + prefixBonus
        + wordBonus
        + exactBonus
    return min(raw, 1)
  }

  private static func isWordStart(_ chars: [Character], _ index: Int) -> Bool {
    if index == 0 {
      return true
    }
    let previous = chars[index - 1]
    if previous.isWhitespace || "-_./".contains(previous) {
      return true
    }
    let current = chars[index]
    return previous.isLowercase && current.isUppercase
  }
}
