import PhotonClipboard
import PhotonCore

extension LauncherViewModel {
  /// Switches the panel to clipboard history. `query` seeds its search field.
  func enterClipboard(query initialQuery: String) {
    guard let clipboard else {
      return
    }
    exitMode(clearingQuery: false)
    lastError = nil
    session = .clipboard
    clipboardShowsResults = !initialQuery.isEmpty
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
    session = .commands
    if query.isEmpty {
      Task { await refresh() }
    } else {
      query = ""
    }
  }

  func clipboardContent() -> LauncherContent {
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
}
