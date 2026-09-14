import SwiftUI

/// Results area of the launcher while it is in file mode.
public struct FileSearchView: View {
  @ObservedObject private var controller: FileSearchController

  public init(controller: FileSearchController) {
    self.controller = controller
  }

  public var body: some View {
    VStack(spacing: 0) {
      content
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      if controller.showsInfo, let file = controller.selected {
        Divider()
        FileInfoView(file: file)
      }
      Divider()
      footer
    }
  }

  @ViewBuilder
  private var content: some View {
    switch controller.status {
    case .idle:
      placeholder("Search files and folders", detail: "Spotlight finds them anywhere on this Mac.")
    case .searching:
      ProgressView("Searching\u{2026}")
    case .unavailable:
      placeholder(
        "Spotlight is unavailable",
        detail: "Check System Settings > Siri & Spotlight, then try again."
      )
    case let .empty(query):
      placeholder("No files match \u{201C}\(query)\u{201D}", detail: nil)
    case .results:
      list
    }
  }

  private var list: some View {
    ScrollViewReader { proxy in
      List(controller.results, selection: $controller.selectedID) { item in
        FileResultRow(file: item.file)
          .tag(item.id)
          .id(item.id)
          .contentShape(Rectangle())
          .onTapGesture {
            controller.select(item.file)
            if controller.performPrimaryAction() {
              controller.onRequestDismiss?()
            }
          }
      }
      .listStyle(.plain)
      .scrollContentBackground(.hidden)
      .onChange(of: controller.selectedID) { _, newValue in
        if let newValue {
          proxy.scrollTo(newValue, anchor: .center)
        }
      }
    }
  }

  private var footer: some View {
    HStack(spacing: 14) {
      if let notice = controller.notice {
        Text(notice)
          .font(.caption)
          .foregroundStyle(.secondary)
      } else {
        ForEach(controller.keyHints) { hint in
          KeyHintView(hint: hint)
        }
      }
      Spacer()
      if controller.isSearching {
        ProgressView()
          .controlSize(.small)
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 6)
    .frame(height: 28)
  }

  private func placeholder(_ title: String, detail: String?) -> some View {
    VStack(spacing: 6) {
      Text(title)
        .foregroundStyle(.secondary)
      if let detail {
        Text(detail)
          .font(.caption)
          .foregroundStyle(.tertiary)
      }
    }
    .multilineTextAlignment(.center)
    .padding()
  }
}

struct FileResultRow: View {
  let file: FileResult

  var body: some View {
    HStack(spacing: 12) {
      Image(nsImage: FileIconCache.shared.icon(for: file))
        .resizable()
        .interpolation(.high)
        .frame(width: 24, height: 24)
      VStack(alignment: .leading, spacing: 2) {
        Text(file.displayName)
          .font(.body.weight(.medium))
          .lineLimit(1)
        Text(PathFormatter.parentDisplay(for: file.path, maxLength: 80))
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
      }
      Spacer(minLength: 12)
      Text(file.kind)
        .font(.caption)
        .foregroundStyle(.tertiary)
        .lineLimit(1)
    }
    .padding(.vertical, 4)
  }
}

struct KeyHintView: View {
  let hint: FileSearchController.KeyHint

  var body: some View {
    HStack(spacing: 4) {
      Text(hint.key)
        .font(.caption2.weight(.semibold))
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(.quaternary))
      Text(hint.label)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }
}

/// Compact metadata strip shown below the list (Cmd+I).
struct FileInfoView: View {
  let file: FileResult

  private struct Row: Identifiable {
    let label: String
    let value: String

    var id: String {
      label
    }
  }

  var body: some View {
    HStack(alignment: .top, spacing: 24) {
      column([
        Row(label: "Kind", value: file.kind),
        Row(label: "Size", value: sizeText),
        Row(label: "Where", value: PathFormatter.abbreviatingHome(file.parentPath))
      ])
      column([
        Row(label: "Created", value: dateText(file.created)),
        Row(label: "Modified", value: dateText(file.modified)),
        Row(label: "Last opened", value: dateText(file.lastUsed))
      ])
    }
    .font(.caption)
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
  }

  private func column(_ rows: [Row]) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      ForEach(rows) { row in
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Text(row.label)
            .foregroundStyle(.secondary)
            .frame(width: 76, alignment: .trailing)
          Text(row.value)
            .lineLimit(1)
            .truncationMode(.middle)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var sizeText: String {
    guard let size = file.size, !file.isFolder else {
      return "\u{2014}"
    }
    return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
  }

  private func dateText(_ date: Date?) -> String {
    date?.formatted(date: .abbreviated, time: .shortened) ?? "\u{2014}"
  }
}
