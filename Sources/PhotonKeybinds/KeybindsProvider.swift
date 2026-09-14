import PhotonCore

/// Phase 2 stub. Hyper key, app hotkeys, and window management live here.
public final class KeybindsProvider: CommandProvider, Sendable {
  public let id = "keybinds"
  public let displayName = "Keybinds"

  public init() {}

  public func commands(matching _: String) async -> [Command] {
    []
  }

  public func execute(_: Command) async throws {}
}
