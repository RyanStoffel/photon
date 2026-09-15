import AppKit

public enum FileActionError: LocalizedError, Sendable {
  case openFailed(String)

  public var errorDescription: String? {
    switch self {
    case let .openFailed(name):
      "Could not open \u{201C}\(name)\u{201D}."
    }
  }
}

/// Open, reveal, and copy-path, shared by the file mode and inline results.
@MainActor
public enum FileActions {
  public static func perform(_ action: FileDefaultAction, on file: FileResult) throws {
    switch action {
    case .open:
      try open(file)
    case .reveal:
      reveal(file)
    }
  }

  public static func open(_ file: FileResult) throws {
    guard NSWorkspace.shared.open(file.url) else {
      throw FileActionError.openFailed(file.displayName)
    }
  }

  public static func reveal(_ file: FileResult) {
    NSWorkspace.shared.activateFileViewerSelecting([file.url])
  }

  public static func copyPath(_ file: FileResult) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(file.path, forType: .string)
  }
}
