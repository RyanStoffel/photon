import AppKit
import Foundation
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

struct LauncherClipboardDetailSplitView: View {
  @ObservedObject var model: LauncherViewModel

  var body: some View {
    HStack(spacing: 0) {
      historyList
        .frame(width: 360)
      Divider()
      if let clipboard = model.clipboard, let item = clipboard.selectedItem {
        ClipboardDetailView(item: item, manager: clipboard.manager)
      } else {
        ContentUnavailableView("No Clipboard Item", systemImage: "clipboard")
      }
    }
  }

  private var historyList: some View {
    ScrollViewReader { proxy in
      ScrollView(.vertical) {
        LazyVStack(alignment: .leading, spacing: 0) {
          Text("Clipboard History")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
          if let clipboard = model.clipboard {
            ForEach(clipboard.results) { item in
              ClipboardLauncherRow(item: item, isSelected: item.id == clipboard.selectedID)
                .id(item.id)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                  clipboard.paste(item)
                }
                .onTapGesture {
                  clipboard.selectedID = item.id
                }
            }
          }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, LauncherLayout.listInset)
      }
      .onChange(of: model.clipboard?.selectedID) { _, selectedID in
        if let selectedID {
          proxy.scrollTo(selectedID, anchor: .center)
        }
      }
    }
  }
}

private struct ClipboardDetailView: View {
  let item: ClipboardItem
  let manager: ClipboardManager
  @State private var fullText: String?
  @State private var image: NSImage?

  var body: some View {
    VStack(spacing: 0) {
      content
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      Divider()
      metadata
        .frame(height: 188, alignment: .top)
    }
    .task(id: item.id) {
      fullText = await manager.fullText(for: item)
      image = await manager.image(for: item)
    }
  }

  @ViewBuilder
  private var content: some View {
    switch item.kind {
    case .image:
      if let image {
        Image(nsImage: image)
          .resizable()
          .interpolation(.high)
          .scaledToFit()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .padding(24)
      } else {
        ProgressView()
          .controlSize(.small)
      }
    case .text, .link:
      ScrollView {
        if item.kind == .link, let text = fullText, let url = URL(string: text) {
          Link(text, destination: url)
            .font(.system(size: 15))
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        } else {
          Text(fullText ?? item.text ?? "")
            .font(.system(size: 14, design: .monospaced))
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .textSelection(.enabled)
        }
      }
      .padding(20)
    case .file:
      ScrollView {
        VStack(alignment: .leading, spacing: 8) {
          ForEach(item.filePaths, id: \.self) { path in
            Label(path, systemImage: "doc")
              .textSelection(.enabled)
          }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(20)
      }
    }
  }

  private var metadata: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Information")
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.secondary)
        .padding(.bottom, 6)
      metadataRow("Source", item.sourceAppName ?? "Unknown app")
      metadataRow("Content type", item.kind.label)
      switch item.kind {
      case .text, .link:
        metadataRow("Characters", "\(displayText.count)")
        metadataRow("Words", "\(wordCount)")
      case .image:
        metadataRow("Dimensions", dimensions)
        metadataRow("Image size", formattedBytes)
      case .file:
        metadataRow("Items", "\(item.filePaths.count)")
        metadataRow("Size", formattedBytes)
      }
      metadataRow("Copied", item.copiedAt.formatted(date: .abbreviated, time: .shortened))
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 12)
  }

  private func metadataRow(_ label: String, _ value: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 16) {
      Text(label)
        .foregroundStyle(.secondary)
      Spacer(minLength: 12)
      Text(value)
        .lineLimit(1)
        .truncationMode(.middle)
        .textSelection(.enabled)
    }
    .font(.system(size: 13))
    .padding(.vertical, 4)
    .overlay(alignment: .bottom) {
      Divider()
    }
  }

  private var displayText: String {
    fullText ?? item.text ?? ""
  }

  private var wordCount: Int {
    displayText.split(whereSeparator: \.isWhitespace).count
  }

  private var dimensions: String {
    guard let width = item.imageWidth, let height = item.imageHeight else {
      return "—"
    }
    return "\(width) × \(height)"
  }

  private var formattedBytes: String {
    ByteCountFormatter.string(fromByteCount: Int64(item.byteCount), countStyle: .file)
  }
}
