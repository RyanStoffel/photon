#if canImport(AppKit) && canImport(SwiftUI)
import AppKit
import SwiftUI

/// Clipboard mode of the launcher panel: results list, preview pane, and a
/// footer with key hints. The search field stays in the launcher; this view
/// only renders what is below it.
public struct ClipboardHistoryView: View {
  @ObservedObject private var model: ClipboardHistoryViewModel

  public init(model: ClipboardHistoryViewModel) {
    self.model = model
  }

  public var body: some View {
    VStack(spacing: 0) {
      content
      Divider()
      footer
    }
  }

  @ViewBuilder
  private var content: some View {
    if model.results.isEmpty {
      emptyState
    } else {
      HStack(spacing: 0) {
        list
          .frame(width: 290)
        Divider()
        ClipboardPreviewView(item: model.selectedItem, manager: model.manager)
      }
    }
  }

  private var list: some View {
    ScrollViewReader { proxy in
      List(model.results, selection: $model.selectedID) { item in
        ClipboardRowView(item: item)
          .tag(item.id)
          .id(item.id)
          .contentShape(Rectangle())
          .onTapGesture(count: 2) {
            model.paste(item)
          }
          .onTapGesture {
            model.selectedID = item.id
          }
          .contextMenu {
            Button(model.manager.settings.pasteBehavior == .paste ? "Paste" : "Copy") {
              model.paste(item)
            }
            Button("Copy Only") {
              model.copy(item)
            }
            Divider()
            Button(item.isPinned ? "Unpin" : "Pin") {
              model.togglePin(item)
            }
            Button("Delete", role: .destructive) {
              model.delete(item)
            }
          }
      }
      .listStyle(.plain)
      .scrollContentBackground(.hidden)
      .onChange(of: model.selectedID) { _, newValue in
        if let newValue {
          proxy.scrollTo(newValue, anchor: .center)
        }
      }
    }
  }

  private struct EmptyCopy {
    let symbol: String
    let title: String
    let detail: String
  }

  private var emptyState: some View {
    let copy = emptyCopy
    return VStack(spacing: 6) {
      Image(systemName: copy.symbol)
        .font(.system(size: 28))
        .foregroundStyle(.tertiary)
      Text(copy.title)
        .font(.body.weight(.medium))
      Text(copy.detail)
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var emptyCopy: EmptyCopy {
    if !model.manager.isEnabled {
      return EmptyCopy(
        symbol: "clipboard",
        title: "Clipboard history is off",
        detail: "Turn it on in Settings > Clipboard to start recording what you copy."
      )
    }
    if model.manager.items.isEmpty {
      return EmptyCopy(
        symbol: "clipboard",
        title: "Nothing copied yet",
        detail: "Copy something in any app and it will show up here."
      )
    }
    return EmptyCopy(
      symbol: "magnifyingglass",
      title: "No matches",
      detail: "Nothing in your clipboard history matches “\(model.query)”."
    )
  }

  private var footer: some View {
    HStack(spacing: 14) {
      if model.isConfirmingClear {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(.orange)
        Text("Clear all \(model.manager.items.count) items, including pinned ones?")
          .foregroundStyle(.primary)
        Spacer()
        KeyHint(key: "↩", label: "Confirm")
        KeyHint(key: "esc", label: "Cancel")
      } else if let notice = model.notice {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(.orange)
        Text(notice.message)
          .foregroundStyle(.primary)
          .lineLimit(1)
        Spacer()
        if notice.offersAccessibility {
          Button("Open Accessibility Settings") {
            model.openAccessibilitySettings()
          }
          .buttonStyle(.link)
          .font(.caption)
        }
      } else {
        KeyHint(key: "↩", label: model.manager.settings.pasteBehavior == .paste ? "Paste" : "Copy")
        KeyHint(key: "⌘↩", label: "Copy")
        KeyHint(key: "⌘P", label: model.selectedItem?.isPinned == true ? "Unpin" : "Pin")
        KeyHint(key: "⌘⌫", label: "Delete")
        Spacer()
        KeyHint(key: "⌘⇧⌫", label: "Clear all")
        KeyHint(key: "esc", label: "Back")
      }
    }
    .font(.caption)
    .foregroundStyle(.secondary)
    .padding(.horizontal, 16)
    .padding(.vertical, 7)
  }
}

struct ClipboardRowView: View {
  let item: ClipboardItem

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: item.kind.symbolName)
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.secondary)
        .frame(width: 22)
      VStack(alignment: .leading, spacing: 2) {
        Text(item.title.isEmpty ? item.kind.label : item.title)
          .font(.body.weight(.medium))
          .lineLimit(1)
          .truncationMode(.tail)
        HStack(spacing: 5) {
          if item.isPinned {
            Image(systemName: "pin.fill")
              .font(.system(size: 9))
          }
          Text(item.copiedAt.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))
          if !item.subtitle.isEmpty {
            Text("·")
            Text(item.subtitle)
              .lineLimit(1)
          }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
      }
      Spacer(minLength: 6)
      Image(nsImage: AppIconCache.shared.icon(forBundleID: item.sourceBundleID))
        .resizable()
        .frame(width: 16, height: 16)
        .help(item.sourceAppName ?? "")
    }
    .padding(.vertical, 3)
  }
}

struct KeyHint: View {
  let key: String
  let label: String

  var body: some View {
    HStack(spacing: 4) {
      Text(key)
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
      Text(label)
    }
  }
}
#endif
