import PhotonCore
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
      emptyState(
        symbol: "doc.text.magnifyingglass",
        title: "Search your files",
        detail: "Matches names and folders in your home directory. Type to begin."
      )
    case .searching:
      searchingState
    case .unavailable:
      emptyState(
        symbol: "exclamationmark.triangle",
        title: "Spotlight is unavailable",
        detail: "Check System Settings > Siri & Spotlight, then try again."
      )
    case let .empty(query):
      emptyState(
        symbol: "magnifyingglass",
        title: "No matches",
        detail: "Nothing in your search scope matches \u{201C}\(query)\u{201D}."
      )
    case .results:
      list
    }
  }

  private var searchingState: some View {
    HStack(spacing: 8) {
      ProgressView()
        .controlSize(.small)
      Text("Searching\u{2026}")
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
      Spacer()
    }
    .padding(.horizontal, 10)
    .frame(height: LauncherLayout.rowHeight)
    .padding(.vertical, LauncherLayout.listInset)
  }

  private var list: some View {
    ScrollViewReader { proxy in
      ScrollView(.vertical) {
        LazyVStack(spacing: 0) {
          ForEach(controller.results) { item in
            FileResultRow(file: item.file, selected: item.id == controller.selectedID)
              .id(item.id)
              .onTapGesture {
                controller.select(item.file)
                if controller.performPrimaryAction() {
                  controller.onRequestDismiss?()
                }
              }
          }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, LauncherLayout.listInset)
      }
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
    .frame(height: LauncherLayout.footerHeight)
  }

  private func emptyState(symbol: String, title: String, detail: String) -> some View {
    VStack(spacing: 6) {
      Image(systemName: symbol)
        .font(.system(size: 28))
        .foregroundStyle(.tertiary)
      Text(title)
        .font(.body.weight(.medium))
      Text(detail)
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

struct FileResultRow: View {
  let file: FileResult
  let selected: Bool

  var body: some View {
    HStack(spacing: 12) {
      Image(nsImage: FileIconCache.shared.icon(for: file))
        .resizable()
        .interpolation(.high)
        .frame(width: LauncherLayout.iconSize, height: LauncherLayout.iconSize)
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(file.displayName)
          .font(.system(size: 14, weight: .medium))
          .lineLimit(1)
          .layoutPriority(1)
        Text(PathFormatter.parentDisplay(for: file.path, maxLength: 56))
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 10)
    .frame(height: LauncherLayout.rowHeight)
    .background(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(selected ? Color.primary.opacity(0.09) : Color.clear)
    )
    .contentShape(Rectangle())
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
