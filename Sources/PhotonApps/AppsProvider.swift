import AppKit
import PhotonCore

public final class AppsProvider: CommandProvider, @unchecked Sendable {
  public let id = "apps"
  public let displayName = "Applications"

  private let index = ApplicationIndex()

  public init() {}

  public func reload() async {
    await Task.detached(priority: .userInitiated) { [index] in
      index.refresh()
    }.value
  }

  public func commands(matching query: String) async -> [Command] {
    let apps = index.applications
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    return apps.compactMap { app in
      if !trimmed.isEmpty {
        let hit = FuzzyMatcher.matches(query: trimmed, candidate: app.name)
          || app.keywords.contains { FuzzyMatcher.matches(query: trimmed, candidate: $0) }
        if !hit {
          return nil
        }
      }
      return Command(
        id: app.id,
        title: app.name,
        subtitle: app.subtitle,
        keywords: app.keywords,
        providerID: id
      )
    }
  }

  public func execute(_ command: Command) async throws {
    let apps = index.applications
    guard let app = apps.first(where: { $0.id == command.id }) else {
      throw AppsProviderError.notFound(command.id)
    }
    try await open(app)
  }

  @MainActor
  private func open(_ app: IndexedApplication) async throws {
    if app.url.pathExtension == "app" {
      let configuration = NSWorkspace.OpenConfiguration()
      configuration.activates = true
      try await NSWorkspace.shared.openApplication(at: app.url, configuration: configuration)
    } else {
      let ok = NSWorkspace.shared.open(app.url)
      if !ok {
        throw AppsProviderError.launchFailed(app.url)
      }
    }
  }
}

public enum AppsProviderError: Error, Sendable {
  case notFound(String)
  case launchFailed(URL)
}
