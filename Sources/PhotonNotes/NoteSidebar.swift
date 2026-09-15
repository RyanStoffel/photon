import Foundation
import SwiftUI

/// One row of the notes sidebar. Pure value derived from a `Note`; no AppKit.
public struct NoteSidebarRow: Identifiable, Hashable, Sendable {
  public static let emptySnippet = "No additional text"

  public let id: String
  public let title: String
  public let snippet: String
  public let dateText: String
  public let modifiedAt: Date

  public init(id: String, title: String, snippet: String, dateText: String, modifiedAt: Date) {
    self.id = id
    self.title = title
    self.snippet = snippet
    self.dateText = dateText
    self.modifiedAt = modifiedAt
  }

  public init(_ note: Note, now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current) {
    let preview = note.preview
    self.init(
      id: note.id,
      title: note.title,
      snippet: preview.isEmpty ? Self.emptySnippet : preview,
      dateText: Self.dateText(for: note.modifiedAt, relativeTo: now, calendar: calendar, locale: locale),
      modifiedAt: note.modifiedAt
    )
  }

  /// Rows for the sidebar, newest first. Ties fall back to the id so the order is stable.
  public static func rows(
    from notes: [Note],
    now: Date = Date(),
    calendar: Calendar = .current,
    locale: Locale = .current
  ) -> [NoteSidebarRow] {
    notes
      .map { NoteSidebarRow($0, now: now, calendar: calendar, locale: locale) }
      .sorted { lhs, rhs in
        if lhs.modifiedAt != rhs.modifiedAt {
          return lhs.modifiedAt > rhs.modifiedAt
        }
        return lhs.id > rhs.id
      }
  }

  /// The date column, following Notes: the time for today, "Yesterday", the weekday for the rest of
  /// the last week, otherwise a short numeric date.
  public static func dateText(
    for date: Date,
    relativeTo now: Date,
    calendar: Calendar = .current,
    locale: Locale = .current
  ) -> String {
    let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
    if calendar.isDate(date, inSameDayAs: now) {
      return date.formatted(style.hour().minute())
    }
    let today = calendar.startOfDay(for: now)
    let day = calendar.startOfDay(for: date)
    let days = calendar.dateComponents([.day], from: day, to: today).day ?? Int.max
    if days == 1 {
      return "Yesterday"
    }
    if days > 1, days < 7 {
      return date.formatted(style.weekday(.wide))
    }
    return date.formatted(style.month(.defaultDigits).day().year(.twoDigits))
  }
}

/// Backing model for the sidebar list: rows, the selected note, and focus requests from ⌘P.
@MainActor
final class NoteSidebarModel: ObservableObject {
  @Published private(set) var rows: [NoteSidebarRow] = []
  @Published private(set) var focusRequests = 0

  /// Bound to the list selection. User changes call `onSelect`; programmatic ones (via `update`) do not.
  @Published var selectedID: String? {
    didSet {
      guard !isUpdating else {
        return
      }
      guard let selectedID else {
        // The list never shows an empty selection: clicking below the last row keeps the current note.
        isUpdating = true
        selectedID = oldValue
        isUpdating = false
        return
      }
      if selectedID != oldValue {
        onSelect?(selectedID)
      }
    }
  }

  var onSelect: ((String) -> Void)?

  private var isUpdating = false

  func update(notes: [Note], selectedID: String?, now: Date = Date()) {
    isUpdating = true
    defer {
      isUpdating = false
    }
    let next = NoteSidebarRow.rows(from: notes, now: now)
    if next != rows {
      rows = next
    }
    if self.selectedID != selectedID {
      self.selectedID = selectedID
    }
  }

  func requestFocus() {
    focusRequests += 1
  }
}

struct NoteSidebarView: View {
  @ObservedObject var model: NoteSidebarModel
  @FocusState private var listFocused: Bool

  var body: some View {
    List(selection: $model.selectedID) {
      ForEach(model.rows) { row in
        NoteSidebarRowView(row: row)
          .tag(row.id)
      }
    }
    .listStyle(.sidebar)
    .scrollContentBackground(.hidden)
    .focused($listFocused)
    .onChange(of: model.focusRequests) { _, _ in
      listFocused = true
    }
    .overlay {
      if model.rows.isEmpty {
        ContentUnavailableView("No Notes", systemImage: "note.text", description: Text("Press ⌘N to create one."))
      }
    }
  }
}

struct NoteSidebarRowView: View {
  let row: NoteSidebarRow

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(row.title)
        .font(.body.weight(.semibold))
        .lineLimit(1)
      HStack(spacing: 6) {
        Text(row.dateText)
        Text(row.snippet)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      .font(.subheadline)
    }
    .padding(.vertical, 4)
    .accessibilityElement(children: .combine)
  }
}
