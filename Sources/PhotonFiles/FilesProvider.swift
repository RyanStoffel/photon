import Foundation
import PhotonCore

public enum FilesProviderError: LocalizedError, Sendable {
  case unknownCommand(String)

  public var errorDescription: String? {
    switch self {
    case let .unknownCommand(id):
      "That file is no longer in the results (\(id))."
    }
  }
}

/// Launcher provider for the Files feature: the "Search Files" command plus
/// filename matches inline in the default results (no Files-mode prefix required).
///
/// Inline results never block the launcher. `commands(matching:)` returns what
/// is cached for the exact query and otherwise starts a debounced Spotlight
/// search in the background; when that finishes, `onInlineResultsChanged`
/// asks the launcher to refresh, the cache now matches, and the rows appear.
public final class FilesProvider: CommandProvider, @unchecked Sendable {
  public static let searchCommandID = "files:search"
  public static let fileCommandPrefix = "file:"

  public let id = "files"
  public let displayName = "Files"

  /// Invoked on the main actor when inline results for the current query are ready.
  /// The query is the trimmed search string; `hasFileHits` is true when at least
  /// one filename match was found (the launcher may promote to Files mode).
  public var onInlineResultsChanged: (@MainActor (_ query: String, _ hasFileHits: Bool) -> Void)?

  private struct InlineCache {
    let query: String
    let files: [FileResult]
  }

  private let lock = NSLock()
  private let engine: FileSearchEngine
  private var settings = FileSearchSettings()
  private var cache: InlineCache?

  @MainActor
  public init(engine: FileSearchEngine = FileSearchEngine()) {
    self.engine = engine
  }

  public var searchCommand: Command {
    Command(
      id: Self.searchCommandID,
      title: "Search Files",
      subtitle: "Find files and folders with Spotlight",
      keywords: ["files", "file", "find", "finder", "spotlight", "folder", "search"],
      providerID: id,
      icon: .symbol(name: "doc.text.magnifyingglass")
    )
  }

  public func update(settings: FileSearchSettings) {
    synchronized {
      self.settings = settings
      cache = nil
    }
  }

  public func commands(matching query: String) async -> [Command] {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    var commands = [searchCommand]
    let (current, cached) = synchronized { (settings, cache) }

    guard current.inlineResults, trimmed.count >= FileSearchSettings.inlineMinimumQueryLength else {
      cancelInlineSearch()
      return commands
    }
    if let cached, cached.query == trimmed {
      commands += cached.files.map(command(for:))
      return commands
    }
    scheduleInlineSearch(query: trimmed, settings: current)
    return commands
  }

  public func execute(_ command: Command) async throws {
    if command.id == Self.searchCommandID {
      return
    }
    let path = Self.path(forCommandID: command.id)
    let (file, action) = synchronized {
      (cache?.files.first { $0.path == path }, settings.defaultAction)
    }
    guard let file else {
      throw FilesProviderError.unknownCommand(command.id)
    }
    try await MainActor.run {
      try FileActions.perform(action, on: file)
    }
  }

  /// Path behind an inline file command, or `nil` for other commands.
  public static func path(forCommandID commandID: String) -> String? {
    guard commandID.hasPrefix(fileCommandPrefix) else {
      return nil
    }
    return String(commandID.dropFirst(fileCommandPrefix.count))
  }

  private func command(for file: FileResult) -> Command {
    Command(
      id: Self.fileCommandPrefix + file.path,
      title: file.displayName,
      subtitle: PathFormatter.parentDisplay(for: file.path, maxLength: 60),
      keywords: [file.fileName],
      providerID: id,
      icon: .fileIcon(path: file.path)
    )
  }

  private func scheduleInlineSearch(query: String, settings: FileSearchSettings) {
    Task { @MainActor [weak self] in
      guard let self else {
        return
      }
      let request = FileSearchEngine.Request(
        query: query,
        settings: settings,
        limit: FileSearchSettings.inlineLimit,
        includeApplications: false
      )
      guard let response = await engine.search(request) else {
        return
      }
      let shown = Array(response.files.prefix(FileSearchSettings.inlineLimit))
      let cache = InlineCache(query: query, files: shown.map(\.file))
      synchronized {
        self.cache = cache
      }
      onInlineResultsChanged?(query, !shown.isEmpty)
    }
  }

  /// Ranked inline hits for `query`, when the cache matches.
  public func inlineRankedFiles(for query: String) -> [RankedFile]? {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    return synchronized {
      guard let cache, cache.query == trimmed, !cache.files.isEmpty else {
        return nil
      }
      return cache.files.enumerated().map { index, file in
        RankedFile(file: file, relevance: Double(FileSearchSettings.inlineLimit - index))
      }
    }
  }

  /// Whether the inline cache currently holds filename hits for `query`.
  public func hasInlineResults(for query: String) -> Bool {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    return synchronized {
      guard let cache, cache.query == trimmed else {
        return false
      }
      return !cache.files.isEmpty
    }
  }

  /// Cancels in-flight inline Spotlight work so Files mode recents/search are not raced.
  @MainActor
  public func prepareForFullSession() {
    engine.cancel()
    synchronized {
      cache = nil
    }
  }

  private func cancelInlineSearch() {
    Task { @MainActor [weak self] in
      self?.prepareForFullSession()
    }
  }

  private func synchronized<T>(_ body: () throws -> T) rethrows -> T {
    lock.lock()
    defer { lock.unlock() }
    return try body()
  }
}
