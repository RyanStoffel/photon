import Foundation

/// Debounced, cancellable Spotlight search. One engine serves one consumer:
/// each new `search` supersedes the previous one, so stale results are never
/// delivered and the panel never flickers between old and new lists.
@MainActor
public final class FileSearchEngine {
  public struct Request: Equatable, Sendable {
    public var query: String
    public var settings: FileSearchSettings
    public var limit: Int
    public var includeApplications: Bool

    public init(query: String, settings: FileSearchSettings, limit: Int, includeApplications: Bool = true) {
      self.query = query
      self.settings = settings
      self.limit = limit
      self.includeApplications = includeApplications
    }
  }

  public struct Response: Sendable {
    public let query: String
    public let files: [RankedFile]
    public let spotlightAvailable: Bool
  }

  public static let defaultDebounce: Duration = .milliseconds(120)

  private let debounce: Duration
  private var generation = 0
  private var runner: SpotlightQueryRunner?

  public init(debounce: Duration = FileSearchEngine.defaultDebounce) {
    self.debounce = debounce
  }

  /// Waits out the debounce window, cancels any in-flight query, runs
  /// Spotlight, and ranks off the main thread. Returns `nil` when a newer
  /// search superseded this one, in which case the caller should do nothing.
  public func search(_ request: Request) async -> Response? {
    generation += 1
    let token = generation
    runner?.cancel()
    runner = nil

    let trimmed = request.query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let queryString = SpotlightQueryBuilder.queryString(
      for: trimmed,
      searchContents: request.settings.searchContents
    ) else {
      return Response(query: trimmed, files: [], spotlightAvailable: true)
    }

    if debounce > .zero {
      try? await Task.sleep(for: debounce)
    }
    guard token == generation, !Task.isCancelled else {
      return nil
    }

    let runner = SpotlightQueryRunner()
    self.runner = runner
    let spotlightRequest = SpotlightQueryRunner.Request(
      queryString: queryString,
      scopes: scopes(for: request.settings),
      scanLimit: max(500, request.limit * 20)
    )
    let outcome: SpotlightQueryRunner.Outcome = await withCheckedContinuation { continuation in
      runner.start(spotlightRequest) { outcome in
        continuation.resume(returning: outcome)
      }
    }
    if self.runner === runner {
      self.runner = nil
    }
    guard token == generation, !outcome.cancelled else {
      return nil
    }

    let ranked = await Task.detached(priority: .userInitiated) {
      let ranked = FileRanker.rank(
        outcome.files,
        query: trimmed,
        excludedFolders: request.settings.excludedFolders,
        includeApplications: request.includeApplications,
        limit: request.limit
      )
      FileIconCache.shared.prefetch(ranked.map(\.file))
      return ranked
    }.value
    guard token == generation else {
      return nil
    }
    return Response(query: trimmed, files: ranked, spotlightAvailable: outcome.spotlightAvailable)
  }

  public func cancel() {
    generation += 1
    runner?.cancel()
    runner = nil
  }

  private func scopes(for settings: FileSearchSettings) -> [String] {
    var scopes = [settings.scope == .computer ? NSMetadataQueryLocalComputerScope : NSMetadataQueryUserHomeScope]
    let extras = FileRanker.normalizedFolders(settings.extraFolders, home: NSHomeDirectory())
    for folder in extras where folder.hasPrefix("/") && !scopes.contains(folder) {
      scopes.append(folder)
    }
    return scopes
  }
}
