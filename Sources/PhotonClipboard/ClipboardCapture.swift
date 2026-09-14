import Foundation

/// Raw pasteboard contents read by the monitor, before they become a history item.
///
/// Priority for the item's kind: file URLs, then text (a link when it is a
/// single URL), then an image. Whatever else was captured is kept as a
/// secondary representation and written back on paste.
public struct ClipboardCapture: Equatable, Sendable {
  /// Images larger than this are dropped rather than stored.
  public static let maxImageBytes = 48 * 1024 * 1024

  public var text: String?
  public var richText: Data?
  public var imagePNG: Data?
  public var imageWidth: Int?
  public var imageHeight: Int?
  public var filePaths: [String]
  public var sourceBundleID: String?
  public var sourceAppName: String?
  public var date: Date

  public init(
    text: String? = nil,
    richText: Data? = nil,
    imagePNG: Data? = nil,
    imageWidth: Int? = nil,
    imageHeight: Int? = nil,
    filePaths: [String] = [],
    sourceBundleID: String? = nil,
    sourceAppName: String? = nil,
    date: Date = Date()
  ) {
    self.text = text
    self.richText = richText
    self.imagePNG = imagePNG
    self.imageWidth = imageWidth
    self.imageHeight = imageHeight
    self.filePaths = filePaths
    self.sourceBundleID = sourceBundleID
    self.sourceAppName = sourceAppName
    self.date = date
  }

  public var primaryKind: ClipboardItemKind? {
    if !filePaths.isEmpty {
      return .file
    }
    if let text, !text.isEmpty {
      return ClipboardContent.isLink(text) ? .link : .text
    }
    if imagePNG != nil {
      return .image
    }
    return nil
  }

  public var contentHash: String? {
    switch primaryKind {
    case .file:
      ClipboardContent.hash(filePaths: filePaths)
    case .text, .link:
      text.map(ClipboardContent.hash(text:))
    case .image:
      imagePNG.map(ClipboardContent.hash(imageData:))
    case nil:
      nil
    }
  }

  /// Builds the index entry. Blob bookkeeping (`byteCount`, truncation flags)
  /// is filled in here; the store writes the actual files.
  public func makeItem(id: UUID = UUID()) -> ClipboardItem? {
    guard let kind = primaryKind, let hash = contentHash else {
      return nil
    }
    var bytes = 0
    var inlineText: String?
    var truncated = false
    if let text, !text.isEmpty {
      bytes += text.utf8.count
      if text.count > ClipboardItem.inlineTextLimit {
        inlineText = String(text.prefix(ClipboardItem.inlineTextLimit))
        truncated = true
      } else {
        inlineText = text
      }
    }
    if let richText {
      bytes += richText.count
    }
    if let imagePNG {
      bytes += imagePNG.count
    }
    return ClipboardItem(
      id: id,
      kind: kind,
      createdAt: date,
      sourceBundleID: sourceBundleID,
      sourceAppName: sourceAppName,
      text: inlineText,
      isTextTruncated: truncated,
      hasRichText: richText != nil,
      hasImage: imagePNG != nil,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      filePaths: filePaths,
      byteCount: bytes,
      contentHash: hash
    )
  }
}
