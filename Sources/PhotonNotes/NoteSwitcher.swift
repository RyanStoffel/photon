import PhotonCore
import SwiftUI

/// Backing model for the ⌘P switcher: fuzzy filter over titles, keyboard selection, create-on-miss.
@MainActor
final class NoteSwitcherModel: ObservableObject {
  @Published var query = "" {
    didSet {
      if query != oldValue {
        refilter()
      }
    }
  }

  @Published private(set) var results: [Note] = []
  @Published var selectedID: String?

  var onOpen: ((String) -> Void)?
  var onCreate: ((String) -> Void)?

  private var all: [Note] = []

  var trimmedQuery: String {
    query.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var canCreate: Bool {
    results.isEmpty && !trimmedQuery.isEmpty
  }

  func update(notes: [Note]) {
    all = notes
    refilter()
  }

  func moveSelection(_ delta: Int) {
    guard !results.isEmpty else {
      return
    }
    let index = results.firstIndex { $0.id == selectedID } ?? 0
    let next = (index + delta + results.count) % results.count
    selectedID = results[next].id
  }

  func openSelection() {
    if let selectedID, results.contains(where: { $0.id == selectedID }) {
      onOpen?(selectedID)
    } else if canCreate {
      onCreate?(trimmedQuery)
    }
  }

  private struct Scored {
    let note: Note
    let score: Double
  }

  private func refilter() {
    let needle = trimmedQuery
    if needle.isEmpty {
      results = all
    } else {
      results = all
        .compactMap { note in
          FuzzyMatcher.score(query: needle, candidate: note.title).map { Scored(note: note, score: $0) }
        }
        .sorted { $0.score > $1.score }
        .map(\.note)
    }
    if !results.contains(where: { $0.id == selectedID }) {
      selectedID = results.first?.id
    }
  }
}

struct NoteSwitcherView: View {
  @ObservedObject var model: NoteSwitcherModel
  @FocusState private var searchFocused: Bool

  var body: some View {
    VStack(spacing: 0) {
      searchField
      Divider()
      if model.results.isEmpty {
        emptyState
      } else {
        list
      }
    }
    .frame(width: 320, height: 380)
    .onAppear {
      searchFocused = true
    }
  }

  private var searchField: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(.secondary)
      TextField("Search notes", text: $model.query)
        .textFieldStyle(.plain)
        .focused($searchFocused)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
  }

  private var list: some View {
    ScrollViewReader { proxy in
      List(model.results, selection: $model.selectedID) { note in
        row(note)
          .tag(note.id)
          .id(note.id)
      }
      .listStyle(.plain)
      .scrollContentBackground(.hidden)
      .onChange(of: model.selectedID) { _, newValue in
        if let newValue {
          proxy.scrollTo(newValue)
        }
      }
    }
  }

  @ViewBuilder
  private var emptyState: some View {
    if model.canCreate {
      Button {
        model.openSelection()
      } label: {
        Label("Create “\(model.trimmedQuery)”", systemImage: "plus.circle")
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .buttonStyle(.plain)
      .padding(12)
      Spacer()
    } else {
      Text("No notes yet")
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private func row(_ note: Note) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(note.title)
        .font(.body.weight(.medium))
        .lineLimit(1)
      HStack(spacing: 6) {
        Text(note.modifiedAt, format: .relative(presentation: .named))
        if !note.preview.isEmpty {
          Text("·")
          Text(note.preview)
            .lineLimit(1)
        }
      }
      .font(.caption)
      .foregroundStyle(.secondary)
    }
    .padding(.vertical, 3)
    .contentShape(Rectangle())
    .onTapGesture {
      model.selectedID = note.id
      model.openSelection()
    }
  }
}
