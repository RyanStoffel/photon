#if canImport(AppKit) && canImport(SwiftUI)
import AppKit
import SwiftUI

/// Right-hand pane of the clipboard view: full text, the image, or the files.
struct ClipboardPreviewView: View {
  /// Longer text is cut for rendering; paste still uses the full payload.
  private static let renderedTextLimit = 20000

  let item: ClipboardItem?
  let manager: ClipboardManager

  @State private var image: NSImage?
  @State private var text: String?
  @State private var isLoading = false

  var body: some View {
    Group {
      if let item {
        VStack(alignment: .leading, spacing: 0) {
          header(item)
          Divider()
          preview(item)
        }
      } else {
        Text("Select an item to preview it")
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .task(id: item?.id) {
      await load()
    }
  }

  private func header(_ item: ClipboardItem) -> some View {
    HStack(spacing: 6) {
      Image(systemName: item.kind.symbolName)
      Text(item.kind.label)
        .fontWeight(.semibold)
      if let app = item.sourceAppName, !app.isEmpty {
        Text("from \(app)")
      }
      Spacer()
      Text(item.copiedAt.formatted(date: .abbreviated, time: .shortened))
    }
    .font(.caption)
    .foregroundStyle(.secondary)
    .lineLimit(1)
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
  }

  @ViewBuilder
  private func preview(_ item: ClipboardItem) -> some View {
    switch item.kind {
    case .text, .link:
      textPreview(item)
    case .image:
      imagePreview
    case .file:
      filePreview(item)
    }
  }

  private func textPreview(_ item: ClipboardItem) -> some View {
    ScrollView {
      Text(String((text ?? item.text ?? "").prefix(Self.renderedTextLimit)))
        .font(.system(.body, design: item.kind == .link ? .monospaced : .default))
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(12)
    }
  }

  @ViewBuilder
  private var imagePreview: some View {
    if let image {
      Image(nsImage: image)
        .resizable()
        .scaledToFit()
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if isLoading {
      ProgressView()
        .controlSize(.small)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      Text("Image is no longer on disk")
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private func filePreview(_ item: ClipboardItem) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 8) {
        ForEach(item.filePaths, id: \.self) { path in
          let exists = FileManager.default.fileExists(atPath: path)
          HStack(spacing: 8) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
              .resizable()
              .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
              Text(URL(fileURLWithPath: path).lastPathComponent)
                .font(.body.weight(.medium))
              Text(exists ? URL(fileURLWithPath: path).deletingLastPathComponent().path : "Missing: \(path)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            }
          }
          .opacity(exists ? 1 : 0.6)
        }
      }
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .topLeading)
    }
  }

  private func load() async {
    image = nil
    text = nil
    guard let item else {
      return
    }
    switch item.kind {
    case .image:
      isLoading = true
      let loaded = await manager.image(for: item)
      guard !Task.isCancelled else {
        return
      }
      image = loaded
      isLoading = false
    case .text, .link:
      if item.isTextTruncated {
        let loaded = await manager.fullText(for: item)
        guard !Task.isCancelled else {
          return
        }
        text = loaded
      }
    case .file:
      break
    }
  }
}
#endif
