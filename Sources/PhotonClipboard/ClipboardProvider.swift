import PhotonCore

/// Phase 2 stub. Clipboard history will live entirely in this module.
public final class ClipboardProvider: CommandProvider, Sendable {
  public let id = "clipboard"
  public let displayName = "Clipboard"

  public init() {}

  public func commands(matching _: String) async -> [Command] {
    []
  }

  public func execute(_: Command) async throws {}
}
