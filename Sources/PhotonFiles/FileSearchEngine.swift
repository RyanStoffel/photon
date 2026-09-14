import Foundation

/// Debounced, cancellable Spotlight search via `mdfind`. One engine serves one
/// consumer: each new `search` supersedes the previous one, so stale results
/// are never delivered and the panel never flickers between old and new lists.
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
  /// `mdfind` on a short substring can scan the whole home folder; expire it so
  /// Files never sits on a stuck Searching panel.
  public static let queryTimeout: Duration = .milliseconds(1800)

  private let debounce: Duration
  private var generation = 0
  private var runners: [MdfindQueryRunner] = []

  public init(debounce: Duration = FileSearchEngine.defaultDebounce) {
    self.debounce = debounce
  }

  /// Waits out the debounce window, cancels any in-flight query, runs
  /// `mdfind` (metadata plus `-name` fallback), and ranks off the main thread.
  /// Returns `nil` when a newer search superseded this one, in which case the
  /// caller should do nothing.
  public func search(_ request: Request) async -> Response? {
    generation += 1
    let token = generation
    cancelRunners()

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

    let folders = onlyInFolders(for: request.settings)
    let scanLimit = max(500, request.limit * 20)
    let terms = SpotlightQueryBuilder.terms(from: trimmed)
    var invocations: [MdfindQueryRunner.Request] = [
      MdfindQueryRunner.Request(queryString: queryString, onlyIn: folders, scanLimit: scanLimit)
    ]
    for term in terms {
      invocations.append(
        MdfindQueryRunner.Request(fileName: term, onlyIn: folders, scanLimit: scanLimit)
      )
    }

    var paths: [String] = []
    var spotlightAvailable = true
    for invocation in invocations {
      guard token == generation, !Task.isCancelled else {
        return nil
      }
      let outcome = await runMdfind(invocation)
      guard token == generation else {
        return nil
      }
      if outcome.cancelled {
        continue
      }
      spotlightAvailable = spotlightAvailable && outcome.spotlightAvailable
      paths.append(contentsOf: outcome.paths)
    }
    guard token == generation else {
      return nil
    }

    let uniquePaths = uniqued(paths)
    let ranked = await Task.detached(priority: .userInitiated) {
      let files = uniquePaths.compactMap(FileResultFactory.file(at:))
      let ranked = FileRanker.rank(
        files,
        query: trimmed,
        excludedFolders: request.settings.excludedFolders,
        includeApplications: request.includeApplications,
        limit: request.limit,
        scope: request.settings.scope,
        extraFolders: request.settings.extraFolders
      )
      FileIconCache.shared.prefetch(ranked.map(\.file))
      return ranked
    }.value
    guard token == generation else {
      return nil
    }
    return Response(query: trimmed, files: ranked, spotlightAvailable: spotlightAvailable)
  }

  public func cancel() {
    generation += 1
    cancelRunners()
  }

  /// Home scope uses `mdfind -onlyin $HOME` (plus extra folders). Computer
  /// scope omits `-onlyin` so Spotlight searches this Mac.
  private func onlyInFolders(for settings: FileSearchSettings) -> [String] {
    var folders: [String] = []
    if settings.scope == .home {
      folders.append(NSHomeDirectory())
    }
    let extras = FileRanker.normalizedFolders(settings.extraFolders, home: NSHomeDirectory())
    for folder in extras where folder.hasPrefix("/") && !folders.contains(folder) {
      folders.append(folder)
    }
    return folders
  }

  private func runMdfind(_ request: MdfindQueryRunner.Request) async -> MdfindQueryRunner.Outcome {
    let runner = MdfindQueryRunner()
    runners.append(runner)
    let outcome: MdfindQueryRunner.Outcome = await withCheckedContinuation { continuation in
      runner.start(request) { outcome in
        continuation.resume(returning: outcome)
      }
      Task {
        try? await Task.sleep(for: FileSearchEngine.queryTimeout)
        runner.expire()
      }
    }
    runners.removeAll { $0 === runner }
    return outcome
  }

  private func cancelRunners() {
    for runner in runners {
      runner.cancel()
    }
    runners = []
  }

  private func uniqued(_ paths: [String]) -> [String] {
    var seen = Set<String>()
    return paths.filter { seen.insert($0).inserted }
  }
}
