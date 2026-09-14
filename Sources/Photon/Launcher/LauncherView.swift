import PhotonClipboard
import PhotonCore
import SwiftUI

/// The launcher panel: search field, the command list (or a feature view), and a footer.
/// Sizes come from `LauncherLayout` so the AppKit window and this view always agree.
struct LauncherView: View {
  @ObservedObject var model: LauncherViewModel
  var onRun: () -> Void

  static let defaultPlaceholder = "Search apps, files, notes and more\u{2026}"

  var body: some View {
    VStack(spacing: 0) {
      searchField
      switch model.content {
      case .searchOnly:
        EmptyView()
      case .rows:
        Hairline()
        if model.session == .clipboard {
          clipboardResultsList
        } else {
          resultsList
        }
      case .fullHeight:
        Hairline()
        featureContent
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      if model.showsCommandList || model.session == .clipboard {
        Hairline()
        if model.session == .clipboard, let clipboard = model.clipboard {
          ClipboardLauncherFooter(model: clipboard)
        } else {
          footer
        }
      }
    }
    .frame(width: model.panelWidth, height: LauncherLayout.height(for: model.content))
    .overlay(
      RoundedRectangle(cornerRadius: LauncherLayout.cornerRadius, style: .continuous)
        .strokeBorder(Color.primary.opacity(0.1), lineWidth: LauncherLayout.hairline)
    )
    .onAppear {
      Task { await model.refresh() }
    }
  }

  // MARK: Search field

  private var searchField: some View {
    HStack(spacing: 12) {
      sessionBadge
      TextField(placeholder, text: $model.query)
        .textFieldStyle(.plain)
        .font(.system(size: 20))
        .onSubmit {
          Task { await run() }
        }
    }
    .padding(.horizontal, 20)
    .frame(height: LauncherLayout.searchFieldHeight)
  }

  @ViewBuilder
  private var sessionBadge: some View {
    if let mode = model.activeMode {
      badge(mode.title)
    }
  }

  private func badge(_ title: String) -> some View {
    Text(title)
      .font(.system(size: 12, weight: .semibold))
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(Capsule().fill(Color.accentColor.opacity(0.18)))
      .foregroundStyle(Color.accentColor)
  }

  private var placeholder: String {
    if model.session == .clipboard {
      "Search clipboard history\u{2026}"
    } else if let mode = model.activeMode {
      mode.placeholder
    } else {
      Self.defaultPlaceholder
    }
  }

  // MARK: Feature views (file search and other modes)

  @ViewBuilder
  private var featureContent: some View {
    if let mode = model.activeMode {
      mode.makeResultsView()
    }
  }

  // MARK: Clipboard list

  private var clipboardResultsList: some View {
    ScrollViewReader { proxy in
      ScrollView(.vertical) {
        LazyVStack(spacing: 0) {
          if let clipboard = model.clipboard {
            if clipboard.results.isEmpty, clipboard.showsCompactEmptyRow {
              clipboardMessageRow(clipboard.compactEmptyMessage)
            } else {
              ForEach(clipboard.results) { item in
                clipboardResultRow(item)
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
    .frame(height: LauncherLayout.listHeight(rowCount: clipboardVisibleRowCount))
  }

  private var clipboardVisibleRowCount: Int {
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

  private func clipboardMessageRow(_ message: String) -> some View {
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
  private func clipboardResultRow(_ item: ClipboardItem) -> some View {
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

  // MARK: Command list

  private var resultsList: some View {
    ScrollViewReader { proxy in
      ScrollView(.vertical) {
        LazyVStack(spacing: 0) {
          if model.rows.isEmpty {
            messageRow
          } else {
            ForEach(model.rows) { row in
              resultRow(row)
                .id(row.id)
            }
          }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, LauncherLayout.listInset)
      }
      .onChange(of: model.selectedID) { _, newValue in
        if let newValue {
          proxy.scrollTo(newValue)
        }
      }
    }
    .frame(height: LauncherLayout.listHeight(rowCount: model.rows.count))
  }

  private var messageRow: some View {
    HStack {
      Text(model.isLoading ? "Indexing applications\u{2026}" : "No results")
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
      Spacer()
    }
    .padding(.horizontal, 10)
    .frame(height: LauncherLayout.rowHeight)
  }

  private func resultRow(_ row: LauncherRow) -> some View {
    let selected = row.id == model.selectedID
    return HStack(spacing: 12) {
      rowIcon(for: row)
        .frame(width: LauncherLayout.iconSize, height: LauncherLayout.iconSize)
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(row.title)
          .font(.system(size: 14, weight: .medium))
          .lineLimit(1)
          .layoutPriority(1)
        if let detail = row.detail {
          Text(detail)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
        }
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
    .onTapGesture {
      model.selectedID = row.id
      Task { await run() }
    }
  }

  @ViewBuilder
  private func rowIcon(for row: LauncherRow) -> some View {
    switch CommandIconCache.shared.resolve(row.icon, fallbackSymbol: symbolName(forProvider: row.providerID)) {
    case let .image(image):
      Image(nsImage: image)
        .resizable()
        .interpolation(.high)
        .frame(width: LauncherLayout.iconSize, height: LauncherLayout.iconSize)
    case let .symbol(name):
      symbolTile(name)
    }
  }

  /// Commands without an app icon get a quiet tile so every row lines up.
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

  private func symbolName(forProvider providerID: String) -> String {
    switch providerID {
    case "apps": "app.fill"
    case "clipboard": "clipboard"
    case "files": "doc"
    case "notes": "note.text"
    default: "circle.grid.3x3"
    }
  }

  // MARK: Footer

  private var footer: some View {
    HStack(spacing: 12) {
      if let lastError = model.lastError {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(.orange)
        Text(lastError)
          .lineLimit(1)
          .truncationMode(.tail)
      } else {
        Image(nsImage: NSApp.applicationIconImage)
          .resizable()
          .interpolation(.high)
          .frame(width: 16, height: 16)
        Text("Photon")
          .fontWeight(.medium)
      }
      Spacer(minLength: 12)
      if let row = model.selectedRow {
        FooterKeyHint(label: row.actionVerb, key: "\u{21B5}")
      }
    }
    .font(.system(size: 12))
    .foregroundStyle(.secondary)
    .padding(.horizontal, 14)
    .frame(height: LauncherLayout.footerHeight)
  }

  private func run() async {
    switch model.session {
    case .clipboard:
      await model.clipboard?.performPrimaryAction()
    case .commands:
      if await model.runSelection() {
        onRun()
      }
    }
  }
}

/// One-point separator that reads on both the light and the dark material.
private struct Hairline: View {
  var body: some View {
    Rectangle()
      .fill(Color.primary.opacity(0.08))
      .frame(height: LauncherLayout.hairline)
  }
}

/// "Open ↵": the label first, then the key in a small cap.
private struct FooterKeyHint: View {
  let label: String
  let key: String

  var body: some View {
    HStack(spacing: 6) {
      Text(label)
      Text(key)
        .font(.system(size: 11, weight: .semibold))
        .frame(minWidth: 14)
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.primary.opacity(0.08)))
    }
  }
}
