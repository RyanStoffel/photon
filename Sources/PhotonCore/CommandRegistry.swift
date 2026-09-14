import Foundation

/// Holds the active providers and fans search / execute out to them.
public final class CommandRegistry: @unchecked Sendable {
  private let lock = NSLock()
  private var providers: [any CommandProvider] = []

  public init() {}

  public func register(_ provider: any CommandProvider) {
    lock.lock()
    defer { lock.unlock() }
    if let index = providers.firstIndex(where: { $0.id == provider.id }) {
      providers[index] = provider
    } else {
      providers.append(provider)
    }
  }

  public func provider(id: String) -> (any CommandProvider)? {
    lock.lock()
    defer { lock.unlock() }
    return providers.first { $0.id == id }
  }

  public var allProviders: [any CommandProvider] {
    lock.lock()
    defer { lock.unlock() }
    return providers
  }

  public func reloadAll() async {
    let snapshot = allProviders
    for provider in snapshot {
      await provider.reload()
    }
  }

  public func search(_ query: String, frecency: FrecencyStore) async -> [RankedCommand] {
    let snapshot = allProviders
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    var ranked: [RankedCommand] = []
    ranked.reserveCapacity(64)

    for provider in snapshot {
      let commands = await provider.commands(matching: query)
      for command in commands {
        let text = textScore(query: trimmed, command: command)
        if text == nil, !trimmed.isEmpty {
          continue
        }
        let freq = frecency.score(id: command.id)
        ranked.append(
          RankedCommand(command: command, textScore: text ?? 0, frecencyScore: freq)
        )
      }
    }

    return ranked.sorted { lhs, rhs in
      if lhs.combinedScore != rhs.combinedScore {
        return lhs.combinedScore > rhs.combinedScore
      }
      return lhs.command.title.localizedCaseInsensitiveCompare(rhs.command.title) == .orderedAscending
    }
  }

  public func execute(_ command: Command) async throws {
    guard let provider = provider(id: command.providerID) else {
      throw CommandRegistryError.unknownProvider(command.providerID)
    }
    try await provider.execute(command)
  }

  private func textScore(query: String, command: Command) -> Double? {
    if query.isEmpty {
      return 0
    }
    if let score = FuzzyMatcher.score(query: query, candidate: command.title) {
      return score
    }
    if command.keywords.contains(where: { FuzzyMatcher.score(query: query, candidate: $0) != nil }) {
      return 0.15
    }
    return nil
  }
}

public enum CommandRegistryError: Error, Sendable, Equatable {
  case unknownProvider(String)
}
