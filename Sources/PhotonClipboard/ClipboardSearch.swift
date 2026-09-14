import Foundation
import PhotonCore

/// Ranks history items for the clipboard view.
///
/// Empty query: pinned items first, then newest first. Otherwise every
/// whitespace-separated token must match somewhere (title, body, file paths,
/// source app, or kind); items are ordered by match quality, with small
/// bonuses for pinned and recent entries.
public enum ClipboardSearch: Sendable {
  public struct Match: Identifiable, Equatable, Sendable {
    public let item: ClipboardItem
    public let score: Double

    public var id: UUID {
      item.id
    }
  }

  public static func rank(_ items: [ClipboardItem], query: String, now: Date = Date()) -> [ClipboardItem] {
    matches(items, query: query, now: now).map(\.item)
  }

  public static func matches(_ items: [ClipboardItem], query: String, now: Date = Date()) -> [Match] {
    let tokens = query
      .lowercased()
      .split(whereSeparator: \.isWhitespace)
      .map(String.init)

    if tokens.isEmpty {
      return items
        .sorted { lhs, rhs in
          if lhs.isPinned != rhs.isPinned {
            return lhs.isPinned
          }
          return lhs.copiedAt > rhs.copiedAt
        }
        .map { Match(item: $0, score: 0) }
    }

    var matches: [Match] = []
    matches.reserveCapacity(items.count)
    for item in items {
      guard let score = score(item, tokens: tokens, now: now) else {
        continue
      }
      matches.append(Match(item: item, score: score))
    }
    return matches.sorted { lhs, rhs in
      if lhs.score != rhs.score {
        return lhs.score > rhs.score
      }
      return lhs.item.copiedAt > rhs.item.copiedAt
    }
  }

  /// `nil` when any token fails to match.
  static func score(_ item: ClipboardItem, tokens: [String], now: Date) -> Double? {
    let title = item.title.lowercased()
    let body = item.searchableBody.lowercased()
    let app = item.sourceAppName?.lowercased() ?? ""
    let kind = item.kind.label.lowercased()

    var total = 0.0
    for token in tokens {
      guard let tokenScore = score(token: token, title: title, body: body, app: app, kind: kind) else {
        return nil
      }
      total += tokenScore
    }
    let relevance = total / Double(tokens.count)
    let ageHours = max(0, now.timeIntervalSince(item.copiedAt) / 3600)
    let recency = 0.1 * pow(0.5, ageHours / 24)
    let pinned = item.isPinned ? 0.1 : 0
    return relevance + recency + pinned
  }

  private static func score(token: String, title: String, body: String, app: String, kind: String) -> Double? {
    if !title.isEmpty, let range = title.range(of: token) {
      let atStart = range.lowerBound == title.startIndex
      let atWordStart = atStart || title[title.index(before: range.lowerBound)].isWhitespace
      var score = 1.0
      if atStart {
        score += 0.3
      } else if atWordStart {
        score += 0.15
      }
      if title == token {
        score += 0.3
      }
      return score
    }
    if !body.isEmpty, body.contains(token) {
      return 0.7
    }
    if !app.isEmpty, app.contains(token) {
      return 0.4
    }
    if kind == token || kind.hasPrefix(token), token.count >= 3 {
      return 0.35
    }
    if !title.isEmpty, let fuzzy = FuzzyMatcher.score(query: token, candidate: title), fuzzy >= 0.3 {
      return fuzzy * 0.5
    }
    return nil
  }
}
