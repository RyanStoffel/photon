import PhotonCore
import SwiftUI

/// One row in the notes switcher overlay.
public struct NoteSwitcherItem: Identifiable, Equatable, Sendable {
  public let id: String
  public let title: String
  public let subtitle: String
  public let isCurrent: Bool
  public let isPinned: Bool
  public let characterCount: Int

  public init(
    id: String,
    title: String,
    subtitle: String,
    isCurrent: Bool,
    isPinned: Bool,
    characterCount: Int
  ) {
    self.id = id
    self.title = title
    self.subtitle = subtitle
    self.isCurrent = isCurrent
    self.isPinned = isPinned
    self.characterCount = characterCount
  }

  public static func items(
    from notes: [Note],
    currentID: String?,
    pinned: Set<String>,
    now: Date = Date()
  ) -> [NoteSwitcherItem] {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .full
    let pinnedNotes = notes.filter { pinned.contains($0.id) }
    let rest = notes.filter { !pinned.contains($0.id) }
    return (pinnedNotes + rest).map { note in
      let count = note.characterCount
      let countLabel = NotesLayout.characterCountLabel(count, capitalized: true)
      let subtitle: String
      if note.id == currentID {
        subtitle = "Current • \(countLabel)"
      } else {
        let opened = formatter.localizedString(for: note.modifiedAt, relativeTo: now)
        subtitle = "Opened \(opened) • \(countLabel)"
      }
      return NoteSwitcherItem(
        id: note.id,
        title: note.title,
        subtitle: subtitle,
        isCurrent: note.id == currentID,
        isPinned: pinned.contains(note.id),
        characterCount: count
      )
    }
  }
}

/// Backing model for the ⌘P switcher: fuzzy filter, pin, delete, keyboard selection.
@MainActor
final class NoteSwitcherModel: ObservableObject {
  @Published var query = "" {
    didSet {
      if query != oldValue {
        refilter()
      }
    }
  }

  @Published private(set) var results: [NoteSwitcherItem] = []
  @Published var selectedID: String?

  var onOpen: ((String) -> Void)?
  var onPin: ((String) -> Void)?
  var onDelete: ((String) -> Void)?

  private var all: [NoteSwitcherItem] = []

  var totalCount: Int {
    all.count
  }

  func update(items: [NoteSwitcherItem], selectedID: String?) {
    all = items
    refilter()
    if selectedID != nil {
      self.selectedID = selectedID
    }
  }

  func moveSelection(_ delta: Int) {
    guard !results.isEmpty else {
      return
    }
    let index = results.firstIndex { $0.id == selectedID } ?? 0
    let next = SelectionNavigation.moving(from: index, by: delta, count: results.count)
    selectedID = results[next].id
  }

  func openSelection() {
    if let selectedID, results.contains(where: { $0.id == selectedID }) {
      onOpen?(selectedID)
    }
  }

  func pinSelection() {
    if let selectedID {
      onPin?(selectedID)
    }
  }

  func deleteSelection() {
    if let selectedID {
      onDelete?(selectedID)
    }
  }

  private func refilter() {
    let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
    if needle.isEmpty {
      results = all
    } else {
      results = all.filter { FuzzyMatcher.matches(query: needle, candidate: $0.title) }
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
      header
      if model.results.isEmpty {
        emptyState
      } else {
        list
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

  private var searchField: some View {
    TextField("Search for notes…", text: $model.query)
      .textFieldStyle(.plain)
      .font(.system(size: 15))
      .focused($searchFocused)
      .padding(.horizontal, 14)
      .padding(.vertical, 12)
  }

  private var header: some View {
    HStack {
      Text("Notes")
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.secondary)
      Spacer()
      Text("\(model.results.count)/\(max(model.totalCount, 1)) Notes")
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.secondary)
      Image(systemName: "info.circle")
        .font(.system(size: 12))
        .foregroundStyle(.tertiary)
    }
    .padding(.horizontal, 14)
    .padding(.bottom, 6)
  }

  private var list: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(spacing: 2) {
          ForEach(model.results) { item in
            row(item)
              .id(item.id)
          }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
      }
      .frame(maxHeight: 280)
      .onChange(of: model.selectedID) { _, newValue in
        if let newValue {
          proxy.scrollTo(newValue)
        }
      }
    }
  }

  private var emptyState: some View {
    Text("No notes")
      .foregroundStyle(.secondary)
      .frame(maxWidth: .infinity)
      .padding(24)
  }

  private func row(_ item: NoteSwitcherItem) -> some View {
    let selected = item.id == model.selectedID
    return HStack(spacing: 8) {
      VStack(alignment: .leading, spacing: 2) {
        Text(item.title)
          .font(.system(size: 13, weight: .semibold))
          .lineLimit(1)
        HStack(spacing: 6) {
          if item.isCurrent {
            Circle()
              .fill(Color.orange)
              .frame(width: 6, height: 6)
          }
          Text(item.subtitle)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
      Spacer(minLength: 8)
      if selected {
        Button {
          model.pinSelection()
        } label: {
          Image(systemName: item.isPinned ? "pin.fill" : "pin")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(item.isPinned ? "Unpin" : "Pin")
        Button {
          model.deleteSelection()
        } label: {
          Image(systemName: "trash")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help("Delete")
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .background(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(selected ? Color.primary.opacity(0.1) : Color.clear)
    )
    .contentShape(Rectangle())
    .onTapGesture {
      model.selectedID = item.id
      model.openSelection()
    }
  }
}
