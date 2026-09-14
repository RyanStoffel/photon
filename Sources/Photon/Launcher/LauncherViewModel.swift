import Combine
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
        if !query.isEmpty {
          clipboardShowsResults = true
        }
        clipboard?.query = query
      case .commands:
        if clipboard != nil, let sub = ClipboardProvider.historyQuery(fromLauncherQuery: query) {
          enterClipboard(query: sub)
        } else if activeMode == nil, let match = prefixMatch(in: query) {
          enter(mode: match.mode, query: match.remainder)
        } else if let activeMode {
          activeMode.update(query: query)
        } else if query.isEmpty, !preferences.showsSuggestions {
          // Compact mode collapses at once instead of waiting for an empty search.
          revealsRecommendations = false
          clearResults()
        } else {
          Task { await refresh() }
        }
      }
      updateContent()
    }
  }

  @Published var results: [RankedCommand] = [] {
    didSet { updateContent() }
  }

  @Published var selectedID: String?
  @Published var isLoading = false
  @Published var lastError: String?
  @Published private(set) var session: LauncherSession = .commands {
    didSet { updateContent() }
  }

  /// Clipboard list stays collapsed until the user types or presses Down (like compact launcher rows).
  @Published private(set) var clipboardShowsResults = false {
    didSet { updateContent() }
  }

  @Published private(set) var activeMode: (any LauncherMode)? {
    didSet { updateContent() }
  }

  /// Down on the empty compact bar reveals frecency recents, like Raycast.
  @Published private(set) var revealsRecommendations = false {
    didSet { updateContent() }
  }

  /// Drives the panel height; `LauncherPanelController` resizes the window when it changes.
  @Published private(set) var content: LauncherContent = .searchOnly

  /// Settings > Appearance values the launcher reads. Set by the panel controller.
  @Published var preferences = LauncherPreferences(showsSuggestions: false, width: .default) {
    didSet {
      guard preferences != oldValue else {
        return
      }
      let toggledSuggestions = preferences.showsSuggestions != oldValue.showsSuggestions
      if toggledSuggestions, query.isEmpty, showsCommandList {
        if preferences.showsSuggestions {
          revealsRecommendations = false
          Task { await refresh() }
        } else {
          revealsRecommendations = false
          clearResults()
        }
      }
      updateContent()
    }
  }

  let registry: CommandRegistry
  var frecency: FrecencyStore
  /// Set by `AppRuntime` once the clipboard feature is available.
  var clipboard: ClipboardHistoryViewModel? {
    didSet {
      clipboardCancellable = clipboard?.objectWillChange
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in
          self?.updateContent()
        }
    }
  }

  private var clipboardCancellable: AnyCancellable?
  private(set) var modes: [any LauncherMode] = []
  private let limit = 30
  private let trailingLimit = 5
  /// Searches finish out of order when typing fast; only the latest one may publish.
  private var searchGeneration = 0

  init(registry: CommandRegistry, frecency: FrecencyStore) {
    self.registry = registry
    self.frecency = frecency
  }

  var panelWidth: Double {
    preferences.width.points
  }

  var rows: [LauncherRow] {
    results.map { LauncherRow(command: $0.command) }
  }

  var selectedRow: LauncherRow? {
    guard let selectedID, let ranked = results.first(where: { $0.id == selectedID }) else {
      return nil
    }
    return LauncherRow(command: ranked.command)
  }

  /// True while the default command list (not a mode or the clipboard) is on screen.
  var showsCommandList: Bool {
    session == .commands && activeMode == nil
  }

  func register(mode: any LauncherMode) {
    modes.removeAll { $0.id == mode.id }
    modes.append(mode)
  }

  func refreshLayout() {
    updateContent()
  }

  func resetForShow() {
    resetTransientUI()
    selectedID = results.first?.id
    if query.isEmpty, !preferences.showsSuggestions {
      clearResults()
    }
  }

  /// Collapse clipboard/mode chrome before the window is ordered out so the next
  /// open cannot inherit a tall panel around a compact SwiftUI root.
  func resetForHide() {
    resetTransientUI()
  }

  /// Closes any auxiliary UI the active mode owns (Quick Look) without leaving the mode.
  func prepareForHide() {
    activeMode?.deactivate()
  }

  func refresh() async {
    guard showsCommandList else {
      return
    }
    if query.isEmpty, !preferences.showsSuggestions, !revealsRecommendations {
      clearResults()
      return
    }
    searchGeneration += 1
    let generation = searchGeneration
    isLoading = results.isEmpty
    let ranked = await registry.search(query, frecency: frecency)
    guard showsCommandList, generation == searchGeneration else {
      return
    }
    results = arrange(ranked, forEmptyQuery: query.isEmpty)
    if !results.contains(where: { $0.id == selectedID }) {
      selectedID = results.first?.id
    }
    isLoading = false
    prefetchIcons(for: results)
  }

  func moveSelection(_ delta: Int) {
    if session == .clipboard {
      guard let clipboard, !clipboard.results.isEmpty else {
        return
      }
      if !clipboardShowsResults {
        clipboardShowsResults = true
        if delta < 0 {
          clipboard.selectLast()
        } else {
          clipboard.selectFirst()
        }
        return
      }
      clipboard.moveSelection(delta)
      return
    }
    if let activeMode {
      activeMode.moveSelection(delta)
      updateContent()
      return
    }
    if showsCommandList, query.isEmpty, results.isEmpty, delta > 0 {
      revealRecommendations()
      Task { await refresh() }
      return
    }
    guard !results.isEmpty else {
      return
    }
    let index = results.firstIndex(where: { $0.id == selectedID }) ?? 0
    let next = (index + delta + results.count) % results.count
    selectedID = results[next].id
  }

  /// Down on the empty bar lists recommended apps and other recents.
  func revealRecommendations() {
    guard showsCommandList, query.isEmpty else {
      return
    }
    revealsRecommendations = true
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
    // Collapse before switching session so the first `updateContent` is compact
    // unless this open already has a filter (and therefore rows to show).
    clipboardShowsResults = !initialQuery.isEmpty
    session = .clipboard
    clipboard.reset()
    if query != initialQuery {
      query = initialQuery
    } else {
      clipboard.query = initialQuery
    }
    updateContent()
  }

  /// Back to the command list with an empty query.
  func exitClipboard() {
    guard session == .clipboard else {
      return
    }
    clipboardShowsResults = false
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
    updateContent()
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

  private func resetTransientUI() {
    clipboardShowsResults = false
    revealsRecommendations = false
    if session == .clipboard {
      session = .commands
    }
    exitMode(clearingQuery: false)
    lastError = nil
    if !query.isEmpty {
      query = ""
    } else {
      updateContent()
    }
  }

  private func clearResults() {
    searchGeneration += 1
    isLoading = false
    if !results.isEmpty {
      results = []
    }
    selectedID = nil
  }

  /// Primary results first; a mode's inline results (never its activation command) trail them
  /// except files, which mix into the main list so a query like `ember` shows Documents
  /// hits without typing "files" first.
  /// An empty query lists suggestions: the few best-ranked (frecency) commands.
  private func arrange(_ ranked: [RankedCommand], forEmptyQuery isSuggestions: Bool) -> [RankedCommand] {
    var primary: [RankedCommand] = []
    var trailing: [RankedCommand] = []
    for item in ranked {
      let mode = mode(forInlineProvider: item.command.providerID)
      if let mode, item.command.id != mode.activationCommandID, mode.id != "files" {
        trailing.append(item)
      } else {
        primary.append(item)
      }
    }
    if isSuggestions {
      return Array(primary.prefix(LauncherLayout.suggestionCount))
    }
    return Array(primary.prefix(limit)) + Array(trailing.prefix(trailingLimit))
  }

  private func updateContent() {
    let next: LauncherContent = switch session {
    case .clipboard:
      clipboardContent()
    case .commands:
      if let activeMode {
        if activeMode.prefersCompactLauncherLayout {
          .searchOnly
        } else {
          .fullHeight
        }
      } else if query.isEmpty, !preferences.showsSuggestions, !revealsRecommendations {
        .searchOnly
      } else {
        .rows(count: results.count, showsCalculatorHero: calculatorHero != nil)
      }
    }
    if next != content {
      content = next
    }
  }

  private func clipboardContent() -> LauncherContent {
    guard let clipboard else {
      return .searchOnly
    }
    if !clipboardShowsResults, query.isEmpty, !clipboard.showsCompactEmptyRow {
      return .searchOnly
    }
    if !clipboard.results.isEmpty {
      return .rows(count: clipboard.results.count, showsCalculatorHero: false)
    }
    if clipboard.showsCompactEmptyRow {
      return .rows(count: 1, showsCalculatorHero: false)
    }
    return .searchOnly
  }

  /// Rows resolve their icon on first draw; this warms the ones below the fold.
  private func prefetchIcons(for ranked: [RankedCommand]) {
    let icons = ranked.compactMap(\.command.icon)
    guard !icons.isEmpty else {
      return
    }
    Task.detached(priority: .utility) {
      CommandIconCache.shared.prefetch(icons)
    }
  }
}
