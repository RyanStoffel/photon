import PhotonCore
import SwiftUI

/// ⌘K command palette for the notes window.
@MainActor
final class NoteActionsModel: ObservableObject {
  @Published var query = "" {
    didSet {
      if query != oldValue {
        refilter()
      }
    }
  }

  @Published private(set) var results: [NoteAction] = NoteAction.catalog
  @Published var selectedID: NoteAction.ID? = NoteAction.catalog.first?.id

  var onRun: ((NoteAction.ID) -> Void)?

  func moveSelection(_ delta: Int) {
    guard !results.isEmpty else {
      return
    }
    let index = results.firstIndex { $0.id == selectedID } ?? 0
    let next = SelectionNavigation.moving(from: index, by: delta, count: results.count)
    selectedID = results[next].id
  }

  func runSelection() {
    if let selectedID {
      onRun?(selectedID)
    }
  }

  private func refilter() {
    results = NoteAction.matching(query)
    if !results.contains(where: { $0.id == selectedID }) {
      selectedID = results.first?.id
    }
  }
}

struct NoteActionsView: View {
  @ObservedObject var model: NoteActionsModel
  @FocusState private var searchFocused: Bool

  var body: some View {
    VStack(spacing: 0) {
      TextField("Search for actions…", text: $model.query)
        .textFieldStyle(.plain)
        .font(.system(size: 15))
        .focused($searchFocused)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
      if model.results.isEmpty {
        Text("No actions")
          .foregroundStyle(.secondary)
          .padding(24)
      } else {
        ScrollViewReader { proxy in
          ScrollView {
            LazyVStack(spacing: 2) {
              ForEach(model.results) { action in
                row(action)
                  .id(action.id)
              }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
          }
          .frame(maxHeight: 360)
          .onChange(of: model.selectedID) { _, newValue in
            if let newValue {
              proxy.scrollTo(newValue)
            }
          }
        }
      }
    }
    .frame(width: NotesLayout.overlayCardWidth)
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
    )
    .onAppear {
      searchFocused = true
    }
  }

  private func row(_ action: NoteAction) -> some View {
    let selected = action.id == model.selectedID
    return HStack(spacing: 10) {
      Image(systemName: action.symbolName)
        .font(.system(size: 13, weight: .semibold))
        .frame(width: 18)
        .foregroundStyle(.secondary)
      Text(action.title)
        .font(.system(size: 13, weight: .medium))
      Spacer(minLength: 8)
      Text(action.shortcut)
        .font(.system(size: 11, weight: .semibold).monospaced())
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
          RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Color.primary.opacity(0.08))
        )
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 7)
    .background(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(selected ? Color.primary.opacity(0.1) : Color.clear)
    )
    .contentShape(Rectangle())
    .onTapGesture {
      model.selectedID = action.id
      model.runSelection()
    }
  }
}
