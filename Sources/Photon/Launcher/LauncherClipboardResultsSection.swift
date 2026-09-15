import PhotonClipboard
import PhotonCore
import SwiftUI

struct LauncherClipboardResultsSection: View {
  @ObservedObject var model: LauncherViewModel

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView(.vertical) {
        LazyVStack(spacing: 0) {
          if let clipboard = model.clipboard {
            if clipboard.results.isEmpty, clipboard.showsCompactEmptyRow {
              messageRow(clipboard.compactEmptyMessage)
            } else {
              ForEach(clipboard.results) { item in
                resultRow(item)
                  .id(item.id)
              }
            }
          }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, LauncherLayout.listInset)
      }
      .onChange(of: model.clipboard?.selectedID) { _, newValue in
        if let newValue {
          proxy.scrollTo(newValue)
        }
      }
    }
    .frame(height: LauncherLayout.listHeight(rowCount: visibleRowCount))
  }

  private var visibleRowCount: Int {
    guard let clipboard = model.clipboard else {
      return 1
    }
    if !clipboard.results.isEmpty {
      return clipboard.results.count
    }
    if clipboard.showsCompactEmptyRow {
      return 1
    }
    return 1
  }

  private func messageRow(_ message: String) -> some View {
    HStack {
      Text(message)
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
      Spacer()
    }
    .padding(.horizontal, 10)
    .frame(height: LauncherLayout.rowHeight)
  }

  @ViewBuilder
  private func resultRow(_ item: ClipboardItem) -> some View {
    let selected = item.id == model.clipboard?.selectedID
    ClipboardLauncherRow(item: item, isSelected: selected)
      .contextMenu {
        if let clipboard = model.clipboard {
          Button(clipboard.manager.settings.pasteBehavior == .paste ? "Paste" : "Copy") {
            clipboard.paste(item)
          }
          Button("Copy Only") {
            clipboard.copy(item)
          }
          Divider()
          Button(item.isPinned ? "Unpin" : "Pin") {
            clipboard.togglePin(item)
          }
          Button("Delete", role: .destructive) {
            clipboard.delete(item)
          }
        }
      }
      .onTapGesture(count: 2) {
        model.clipboard?.paste(item)
      }
      .onTapGesture {
        model.clipboard?.selectedID = item.id
      }
  }
}
