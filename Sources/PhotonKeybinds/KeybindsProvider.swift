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
        providerID: id,
        icon: .symbol(name: action.symbolName)
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

public extension WindowAction {
  /// SF Symbol that sketches the layout in the launcher row.
  var symbolName: String {
    switch self {
    case .leftHalf, .leftTwoThirds: "rectangle.lefthalf.inset.filled"
    case .rightHalf, .rightTwoThirds: "rectangle.righthalf.inset.filled"
    case .topHalf: "rectangle.tophalf.inset.filled"
    case .bottomHalf: "rectangle.bottomhalf.inset.filled"
    case .topLeftQuarter: "rectangle.inset.topleft.filled"
    case .topRightQuarter: "rectangle.inset.topright.filled"
    case .bottomLeftQuarter: "rectangle.inset.bottomleft.filled"
    case .bottomRightQuarter: "rectangle.inset.bottomright.filled"
    case .leftThird: "rectangle.leadingthird.inset.filled"
    case .centerThird, .center: "rectangle.center.inset.filled"
    case .rightThird: "rectangle.trailingthird.inset.filled"
    case .maximize, .almostMaximize: "rectangle.inset.filled"
    case .nextDisplay: "rectangle.righthalf.inset.filled.arrow.right"
    case .previousDisplay: "rectangle.lefthalf.inset.filled.arrow.left"
    case .restore: "arrow.uturn.backward"
    }
  }
}
