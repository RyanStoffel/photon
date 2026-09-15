/// A self-contained feature that can contribute launcher results.
///
/// Implement this in the feature module (`PhotonNotes`, `PhotonFiles`, …)
/// and register the type in `AppRuntime`. Prefer a new file over editing
/// this protocol.
public protocol CommandProvider: Sendable {
  var id: String { get }
  var displayName: String { get }

  func reload() async
  func commands(matching query: String) async -> [Command]
  func execute(_ command: Command) async throws
}

public extension CommandProvider {
  func reload() async {}
}
