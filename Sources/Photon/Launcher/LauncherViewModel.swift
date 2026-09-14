import PhotonCore
import SwiftUI

@MainActor
final class LauncherViewModel: ObservableObject {
  @Published var query = "" {
    didSet {
      if query != oldValue {
        Task { await refresh() }
      }
    }
  }

  @Published var results: [RankedCommand] = []
  @Published var selectedID: String?
  @Published var isLoading = false
  @Published var lastError: String?

  let registry: CommandRegistry
  var frecency: FrecencyStore
  private let limit = 30

  init(registry: CommandRegistry, frecency: FrecencyStore) {
    self.registry = registry
    self.frecency = frecency
  }

  func resetForShow() {
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
    do {
      try await registry.execute(ranked.command)
      frecency.recordUse(id: ranked.command.id)
      lastError = nil
    } catch {
      lastError = error.localizedDescription
    }
  }
}
