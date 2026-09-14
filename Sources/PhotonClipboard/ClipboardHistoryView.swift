#if canImport(AppKit) && canImport(SwiftUI)
import AppKit
import PhotonCore
import SwiftUI

/// Footer for clipboard mode in the launcher panel (mode label and key hints).
public struct ClipboardLauncherFooter: View {
  @ObservedObject private var model: ClipboardHistoryViewModel

  public init(model: ClipboardHistoryViewModel) {
    self.model = model
  }

  public var body: some View {
    HStack(spacing: 12) {
      if model.isConfirmingClear {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(.orange)
        Text("Clear all \(model.manager.items.count) items, including pinned ones?")
          .foregroundStyle(.primary)
          .lineLimit(1)
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
        Image(systemName: "clipboard")
          .font(.system(size: 12, weight: .medium))
        Text("Clipboard")
          .fontWeight(.medium)
        if let hint = model.footerEmptyHint {
          Text("·")
          Text(hint)
            .lineLimit(1)
        }
        Spacer(minLength: 12)
        KeyHint(key: "↩", label: model.manager.settings.pasteBehavior == .paste ? "Paste" : "Copy")
        KeyHint(key: "⌘↩", label: "Copy")
        KeyHint(key: "⌘P", label: model.selectedItem?.isPinned == true ? "Unpin" : "Pin")
        KeyHint(key: "⌘⌫", label: "Delete")
        KeyHint(key: "⌘⇧⌫", label: "Clear all")
        KeyHint(key: "esc", label: "Back")
      }
    }
    .font(.system(size: 12))
    .foregroundStyle(.secondary)
    .padding(.horizontal, 14)
    .frame(height: LauncherLayout.footerHeight)
  }
}

/// One clipboard history row, aligned with launcher command rows.
public struct ClipboardLauncherRow: View {
  let item: ClipboardItem
  let isSelected: Bool

  public init(item: ClipboardItem, isSelected: Bool) {
    self.item = item
    self.isSelected = isSelected
  }

  public var body: some View {
    HStack(spacing: 12) {
      symbolTile(item.kind.symbolName)
        .frame(width: LauncherLayout.iconSize, height: LauncherLayout.iconSize)
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(item.title.isEmpty ? item.kind.label : item.title)
          .font(.system(size: 14, weight: .medium))
          .lineLimit(1)
          .layoutPriority(1)
        HStack(spacing: 4) {
          if item.isPinned {
            Image(systemName: "pin.fill")
              .font(.system(size: 9))
          }
          Text(item.copiedAt.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .lineLimit(1)
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 10)
    .frame(height: LauncherLayout.rowHeight)
    .background(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(isSelected ? Color.primary.opacity(0.09) : Color.clear)
    )
    .contentShape(Rectangle())
  }

  private func symbolTile(_ name: String) -> some View {
    ZStack {
      RoundedRectangle(cornerRadius: 7, style: .continuous)
        .fill(Color.primary.opacity(0.08))
      Image(systemName: name)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.secondary)
    }
    .frame(width: LauncherLayout.iconSize - 2, height: LauncherLayout.iconSize - 2)
  }
}

public struct KeyHint: View {
  let key: String
  let label: String

  public init(key: String, label: String) {
    self.key = key
    self.label = label
  }

  public var body: some View {
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
