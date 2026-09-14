import Foundation
import PhotonCore

/// File-name fuzzy matching: same subsequence rules as the app launcher, with
/// separators (spaces, underscores, punctuation) ignored so `ember_individual`
/// matches `Ember_Individual_Pitch`.
enum FileFuzzyMatcher: Sendable {
  static func normalize(_ text: String) -> String {
    let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    return folded.unicodeScalars
      .filter { CharacterSet.alphanumerics.contains($0) }
      .map(String.init)
      .joined()
  }

  static func matches(query: String, candidate: String) -> Bool {
    score(query: query, candidate: candidate) != nil
  }

  static func score(query: String, candidate: String) -> Double? {
    let needle = normalize(query)
    guard !needle.isEmpty else {
      return 1
    }
    let hay = normalize(candidate)
    guard !hay.isEmpty else {
      return nil
    }
    if hay == needle {
      return 1
    }
    return FuzzyMatcher.score(query: needle, candidate: hay)
  }
}
