import PhotonCore

/// Phase 2 stub. Spotlight file search will live entirely in this module.
public final class FilesProvider: CommandProvider, Sendable {
  public let id = "files"
  public let displayName = "Files"

  public init() {}

  public func commands(matching _: String) async -> [Command] {
    []
  }

  public func execute(_: Command) async throws {}
}
