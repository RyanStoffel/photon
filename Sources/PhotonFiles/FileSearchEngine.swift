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
  /// `mdfind` (metadata plus `-name`) and a bounded filesystem fallback, then
  /// ranks off the main thread.
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

    let home = NSHomeDirectory()
    let fallbackTask = Task.detached(priority: .userInitiated) {
      FileSystemFallbackSearch.paths(
        matching: trimmed,
        roots: request.settings.grantedFolders,
        home: home,
        resultLimit: scanLimit
      )
    }
    let outcomes = await withTaskGroup(of: MdfindQueryRunner.Outcome.self) { group in
      for invocation in invocations {
        group.addTask {
          await self.runMdfind(invocation)
        }
      }
      var collected: [MdfindQueryRunner.Outcome] = []
      for await outcome in group {
        collected.append(outcome)
      }
      return collected
    }
    guard token == generation, !Task.isCancelled else {
      fallbackTask.cancel()
      return nil
    }

    let fallbackPaths = await fallbackTask.value
    guard token == generation, !Task.isCancelled else {
      return nil
    }
    let completedOutcomes = outcomes.filter { !$0.cancelled }
    let spotlightAvailable = completedOutcomes.allSatisfy(\.spotlightAvailable)
    let fixturePaths = nativeParityGrantedFixtures(settings: request.settings)
    let uniquePaths = uniqued(completedOutcomes.flatMap(\.paths) + fallbackPaths + fixturePaths)
    let ranked = await Task.detached(priority: .userInitiated) {
      let files = uniquePaths.compactMap(FileResultFactory.file(at:))
      let ranked = FileRanker.rank(
        files,
        query: trimmed,
        excludedFolders: request.settings.excludedFolders,
        includeApplications: request.includeApplications,
        limit: request.limit,
        scope: request.settings.scope,
        extraFolders: request.settings.extraFolders + request.settings.grantedFolders
      )
      FileIconCache.shared.prefetch(ranked.map(\.file))
      return ranked
    }.value
    guard token == generation else {
      return nil
    }
    return Response(query: trimmed, files: ranked, spotlightAvailable: spotlightAvailable)
  }

  /// Loads recent documents for the empty Files view. Spotlight provides the
  /// system-wide candidates; runtime fixtures may add explicit paths for the
  /// packaged-app visual gate.
  public func recent(settings: FileSearchSettings, limit: Int) async -> Response? {
    generation += 1
    let token = generation
    cancelRunners()
    let request = MdfindQueryRunner.Request(
      queryString: "kMDItemLastUsedDate = '*' && kMDItemContentTypeTree = 'public.content'",
      onlyIn: onlyInFolders(for: settings),
      scanLimit: max(300, limit * 10)
    )
    let outcome = await runMdfind(request)
    guard token == generation, !Task.isCancelled else {
      return nil
    }
    let fixturePaths = ProcessInfo.processInfo.environment["PHOTON_NATIVE_PARITY_RECENT_FILES"]?
      .split(separator: ":")
      .map(String.init) ?? []
    let fixtureFiles = fixturePaths.compactMap(FileResultFactory.file(at:))
    let fixtureSet = Set(fixtureFiles.map(\.path))
    let discoveredFiles = uniqued(outcome.paths)
      .compactMap(FileResultFactory.file(at:))
      .filter { !$0.isApplication && !fixtureSet.contains($0.path) }
      .sorted { lhs, rhs in
        let left = lhs.lastUsed ?? lhs.modified ?? lhs.created ?? .distantPast
        let right = rhs.lastUsed ?? rhs.modified ?? rhs.created ?? .distantPast
        if left != right {
          return left > right
        }
        return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
      }
    let files = fixtureFiles + discoveredFiles
    let recent = Array(files.prefix(limit)).enumerated().map { index, file in
      RankedFile(file: file, relevance: Double(limit - index))
    }
    FileIconCache.shared.prefetch(recent.map(\.file))
    return Response(query: "", files: recent, spotlightAvailable: outcome.spotlightAvailable)
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
    let extras = FileRanker.normalizedFolders(
      settings.extraFolders + settings.grantedFolders,
      home: NSHomeDirectory()
    )
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

  private func nativeParityGrantedFixtures(settings: FileSearchSettings) -> [String] {
    let fixtures = ProcessInfo.processInfo.environment["PHOTON_NATIVE_PARITY_GRANTED_FILES"]?
      .split(separator: ":")
      .map(String.init) ?? []
    return fixtures.filter { fixture in
      settings.grantedFolders.contains { folder in
        fixture == folder || fixture.hasPrefix(folder + "/")
      }
    }
  }
}
