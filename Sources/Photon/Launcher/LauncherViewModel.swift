import PhotonClipboard
import PhotonCore
import SwiftUI

/// What the panel shows below the search field. Clipboard is its own session
/// (landed in GH-3). File search uses the `LauncherMode` protocol on top of
/// `.commands`. Unify these later (see the chore issue).
enum LauncherSession: Equatable {
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
      switch session {
      case .clipboard:
        clipboard?.query = query
      case .commands:
        if clipboard != nil, let sub = ClipboardProvider.historyQuery(fromLauncherQuery: query) {
          enterClipboard(query: sub)
        } else if activeMode == nil, let match = prefixMatch(in: query) {
          enter(mode: match.mode, query: match.remainder)
        } else if let activeMode {
          activeMode.update(query: query)
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
  @Published private(set) var session: LauncherSession = .commands
  @Published private(set) var activeMode: (any LauncherMode)?

  let registry: CommandRegistry
  var frecency: FrecencyStore
  /// Set by `AppRuntime` once the clipboard feature is available.
  var clipboard: ClipboardHistoryViewModel?
  private(set) var modes: [any LauncherMode] = []
  private let limit = 30
  private let trailingLimit = 5

  init(registry: CommandRegistry, frecency: FrecencyStore) {
    self.registry = registry
    self.frecency = frecency
  }

  func register(mode: any LauncherMode) {
    modes.removeAll { $0.id == mode.id }
    modes.append(mode)
  }

  func resetForShow() {
    session = .commands
    exitMode(clearingQuery: false)
    query = ""
    lastError = nil
    selectedID = results.first?.id
  }

  /// Closes any auxiliary UI the active mode owns (Quick Look) without leaving the mode.
  func prepareForHide() {
    activeMode?.deactivate()
  }

  func refresh() async {
    guard session == .commands, activeMode == nil else {
      return
    }
    isLoading = results.isEmpty
    let ranked = await registry.search(query, frecency: frecency)
    guard session == .commands, activeMode == nil else {
      return
    }
    results = arrange(ranked)
    if !results.contains(where: { $0.id == selectedID }) {
      selectedID = results.first?.id
    }
    isLoading = false
  }

  func moveSelection(_ delta: Int) {
    if session == .clipboard {
      clipboard?.moveSelection(delta)
      return
    }
    if let activeMode {
      activeMode.moveSelection(delta)
      return
    }
    guard !results.isEmpty else {
      return
    }
    let index = results.firstIndex(where: { $0.id == selectedID }) ?? 0
    let next = (index + delta + results.count) % results.count
    selectedID = results[next].id
  }

  /// Runs the selection. Returns true when the launcher should hide.
  func runSelection() async -> Bool {
    if session == .clipboard {
      await clipboard?.performPrimaryAction()
      return false
    }
    if let activeMode {
      return activeMode.performPrimaryAction()
    }
    guard let selectedID, let ranked = results.first(where: { $0.id == selectedID }) else {
      return false
    }
    if ranked.command.id == ClipboardProvider.historyCommandID, clipboard != nil {
      frecency.recordUse(id: ranked.command.id)
      lastError = nil
      enterClipboard(query: "")
      return false
    }
    if let mode = modes.first(where: { $0.activationCommandID == ranked.command.id }) {
      frecency.recordUse(id: ranked.command.id)
      lastError = nil
      enter(mode: mode, query: "")
      return false
    }
    do {
      try await registry.execute(ranked.command)
      frecency.recordUse(id: ranked.command.id)
      lastError = nil
      return true
    } catch {
      lastError = error.localizedDescription
      return false
    }
  }

  // MARK: Clipboard session

  /// Switches the panel to clipboard history. `query` seeds its search field.
  func enterClipboard(query initialQuery: String) {
    guard let clipboard else {
      return
    }
    exitMode(clearingQuery: false)
    lastError = nil
    session = .clipboard
    clipboard.reset()
    if query != initialQuery {
      query = initialQuery
    } else {
      clipboard.query = initialQuery
    }
  }

  /// Back to the command list with an empty query.
  func exitClipboard() {
    guard session == .clipboard else {
      return
    }
    session = .commands
    if query.isEmpty {
      Task { await refresh() }
    } else {
      query = ""
    }
  }

  // MARK: Feature modes (file search today)

  func enter(mode: any LauncherMode, query: String) {
    if session == .clipboard {
      session = .commands
    }
    activeMode?.deactivate()
    activeMode = mode
    lastError = nil
    if self.query != query {
      self.query = query
    }
    mode.activate(query: query)
  }

  func exitMode(clearingQuery: Bool = true) {
    guard let activeMode else {
      return
    }
    activeMode.deactivate()
    self.activeMode = nil
    if clearingQuery {
      query = ""
      Task { await refresh() }
    }
  }

  func mode(forInlineProvider providerID: String) -> (any LauncherMode)? {
    modes.first { $0.inlineProviderID == providerID }
  }

  private func prefixMatch(in query: String) -> (mode: any LauncherMode, remainder: String)? {
    let lowered = query.lowercased()
    for mode in modes {
      for prefix in mode.prefixes where lowered.hasPrefix(prefix.lowercased()) {
        return (mode, String(query.dropFirst(prefix.count)))
      }
    }
    return nil
  }

  /// Primary results first; a mode's inline results (never its activation command) trail them.
  private func arrange(_ ranked: [RankedCommand]) -> [RankedCommand] {
    var primary: [RankedCommand] = []
    var trailing: [RankedCommand] = []
    for item in ranked {
      let mode = mode(forInlineProvider: item.command.providerID)
      if let mode, item.command.id != mode.activationCommandID {
        trailing.append(item)
      } else {
        primary.append(item)
      }
    }
    return Array(primary.prefix(limit)) + Array(trailing.prefix(trailingLimit))
  }
}
