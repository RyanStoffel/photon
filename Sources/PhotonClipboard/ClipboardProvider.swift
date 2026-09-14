import Foundation
import PhotonCore

/// Launcher entry point for clipboard history.
///
/// Contributes one command, "Clipboard History", and understands the `cb` /
/// `clipboard` prefixes. Running the command switches the launcher panel into
/// the clipboard view; the app wires `openHistory` to do that.
public final class ClipboardProvider: CommandProvider, @unchecked Sendable {
  public static let historyCommandID = "clipboard:history"
  public static let prefixes = ["cb", "clipboard"]

  public let id = "clipboard"
  public let displayName = "Clipboard"

  private let lock = NSLock()
  private var openHistoryHandler: (@Sendable () -> Void)?

  public init() {}

  /// Called when the history command runs. Set by `AppRuntime`.
  public var openHistory: (@Sendable () -> Void)? {
    get {
      lock.lock()
      defer { lock.unlock() }
      return openHistoryHandler
    }
    set {
      lock.lock()
      defer { lock.unlock() }
      openHistoryHandler = newValue
    }
  }

  public func commands(matching _: String) async -> [Command] {
    [
      Command(
        id: Self.historyCommandID,
        title: "Clipboard History",
        subtitle: "Search, paste, and pin what you copied",
        keywords: Self.prefixes + ["paste", "history", "copy"],
        providerID: id,
        icon: .symbol(name: "clipboard")
      )
    ]
  }

  public func execute(_ command: Command) async throws {
    guard command.id == Self.historyCommandID else {
      throw ClipboardProviderError.unknownCommand(command.id)
    }
    openHistory?()
  }

  /// `"cb foo"` → `"foo"`, `"clipboard "` → `""`, `"cbx"` → `nil`.
  ///
  /// A prefix only counts once it is followed by a space, so typing an app
  /// name that happens to start with `cb` keeps showing app results.
  public static func historyQuery(fromLauncherQuery query: String) -> String? {
    let lowered = query.lowercased()
    for prefix in prefixes where lowered.hasPrefix(prefix + " ") {
      return String(query.dropFirst(prefix.count).drop(while: { $0 == " " }))
    }
    return nil
  }
}

public enum ClipboardProviderError: Error, Sendable, Equatable {
  case unknownCommand(String)
}
