import PhotonClipboard
import PhotonCore
import SwiftUI

/// What the panel shows below the search field.
enum LauncherMode: Equatable {
  case commands
  case clipboard
}

@MainActor
final class LauncherViewModel: ObservableObject {
  @Published var query = "" {
    didSet {
      guard query != oldValue else {
        return
      }
      switch mode {
      case .clipboard:
        clipboard?.query = query
      case .commands:
        if clipboard != nil, let sub = ClipboardProvider.historyQuery(fromLauncherQuery: query) {
          enterClipboard(query: sub)
        } else {
          Task { await refresh() }
        }
      }
    }
  }

  @Published var results: [RankedCommand] = []
  @Published var selectedID: String?
  @Published var isLoading = false
  @Published var lastError: String?
  @Published private(set) var mode: LauncherMode = .commands

  let registry: CommandRegistry
  var frecency: FrecencyStore
  /// Set by `AppRuntime` once the clipboard feature is available.
  var clipboard: ClipboardHistoryViewModel?
  private let limit = 30

  init(registry: CommandRegistry, frecency: FrecencyStore) {
    self.registry = registry
    self.frecency = frecency
  }

  func resetForShow() {
    mode = .commands
    query = ""
    lastError = nil
    selectedID = results.first?.id
  }

  func refresh() async {
    isLoading = results.isEmpty
    let ranked = await registry.search(query, frecency: frecency)
    results = Array(ranked.prefix(limit))
    if let selectedID, results.contains(where: { $0.id == selectedID }) {
      // keep
    } else {
      selectedID = results.first?.id
    }
    isLoading = false
  }

  func moveSelection(_ delta: Int) {
    guard !results.isEmpty else {
      return
    }
    let index = results.firstIndex(where: { $0.id == selectedID }) ?? 0
    let next = (index + delta + results.count) % results.count
    selectedID = results[next].id
  }

  func runSelection() async {
    guard let selectedID, let ranked = results.first(where: { $0.id == selectedID }) else {
      return
    }
    if ranked.command.id == ClipboardProvider.historyCommandID, clipboard != nil {
      frecency.recordUse(id: ranked.command.id)
      lastError = nil
      enterClipboard(query: "")
      return
    }
    do {
      try await registry.execute(ranked.command)
      frecency.recordUse(id: ranked.command.id)
      lastError = nil
    } catch {
      lastError = error.localizedDescription
    }
  }

  // MARK: Clipboard mode

  /// Switches the panel to clipboard history. `query` seeds its search field.
  func enterClipboard(query initialQuery: String) {
    guard let clipboard else {
      return
    }
    lastError = nil
    mode = .clipboard
    clipboard.reset()
    if query != initialQuery {
      query = initialQuery
    } else {
      clipboard.query = initialQuery
    }
  }

  /// Back to the command list with an empty query.
  func exitClipboard() {
    guard mode == .clipboard else {
      return
    }
    mode = .commands
    if query.isEmpty {
      Task { await refresh() }
    } else {
      query = ""
    }
  }
}
