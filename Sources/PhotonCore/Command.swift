/// A single launcher result. Providers own identity, copy, and execution.
public struct Command: Identifiable, Hashable, Sendable {
  public let id: String
  public let title: String
  public let subtitle: String
  public let keywords: [String]
  public let providerID: String

  public init(
    id: String,
    title: String,
    subtitle: String = "",
    keywords: [String] = [],
    providerID: String
  ) {
    self.id = id
    self.title = title
    self.subtitle = subtitle
    self.keywords = keywords
    self.providerID = providerID
  }
}

/// A command plus the scores the launcher used to rank it.
public struct RankedCommand: Identifiable, Sendable {
  public var id: String {
    command.id
  }

  public let command: Command
  public let textScore: Double
  public let frecencyScore: Double

  public var combinedScore: Double {
    textScore + frecencyScore
  }

  public init(command: Command, textScore: Double, frecencyScore: Double) {
    self.command = command
    self.textScore = textScore
    self.frecencyScore = frecencyScore
  }
}
