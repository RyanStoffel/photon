import PhotonCore

/// Phase 2 stub. Notes will live entirely in this module.
public final class NotesProvider: CommandProvider, Sendable {
  public let id = "notes"
  public let displayName = "Notes"

  public init() {}

  public func commands(matching _: String) async -> [Command] {
    []
  }

  public func execute(_: Command) async throws {}
}
