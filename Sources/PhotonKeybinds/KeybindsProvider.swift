import PhotonCore

/// Exposes the window commands in the launcher ("Left Half", "Maximize", ...).
public final class KeybindsProvider: CommandProvider, Sendable {
  public let id = "keybinds"
  public let displayName = "Keybinds"

  private static let commandPrefix = "window:"
  private let controller: KeybindsController

  public init(controller: KeybindsController) {
    self.controller = controller
  }

  public func commands(matching query: String) async -> [Command] {
    let configuration = await controller.currentConfiguration
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    return WindowAction.allCases.compactMap { action in
      let keywords = ["window", "layout"] + action.keywords
      if !trimmed.isEmpty {
        let hit = FuzzyMatcher.matches(query: trimmed, candidate: action.title)
          || keywords.contains { FuzzyMatcher.matches(query: trimmed, candidate: $0) }
        if !hit {
          return nil
        }
      }
      let shortcut = configuration.shortcut(for: action)?.displayString
      return Command(
        id: Self.commandPrefix + action.rawValue,
        title: action.title,
        subtitle: shortcut.map { "Window · \($0)" } ?? "Window",
        keywords: keywords,
        providerID: id
      )
    }
  }

  public func execute(_ command: Command) async throws {
    guard command.id.hasPrefix(Self.commandPrefix),
          let action = WindowAction(rawValue: String(command.id.dropFirst(Self.commandPrefix.count)))
    else {
      throw KeybindsProviderError.unknownCommand(command.id)
    }
    try await controller.perform(action)
  }
}

public enum KeybindsProviderError: Error, Sendable {
  case unknownCommand(String)
}
