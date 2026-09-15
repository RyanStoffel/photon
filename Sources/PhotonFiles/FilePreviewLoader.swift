import AppKit
import Combine
import Foundation
import QuickLookThumbnailing

@MainActor
final class FilePreviewLoader: ObservableObject {
  @Published private(set) var image: NSImage?
  @Published private(set) var isLoading = false

  private var task: Task<Void, Never>?

  func load(_ file: FileResult, size: CGSize, scale: CGFloat) {
    task?.cancel()
    image = nil
    isLoading = true
    task = Task {
      let request = QLThumbnailGenerator.Request(
        fileAt: file.url,
        size: size,
        scale: scale,
        representationTypes: [.thumbnail, .icon]
      )
      let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
      guard !Task.isCancelled else {
        return
      }
      image = representation?.nsImage ?? FileIconCache.shared.icon(for: file)
      isLoading = false
    }
  }
}
