import Foundation

/// What a history entry primarily holds. Secondary representations (RTF next
/// to text, an image rendition next to text) ride along and are written back on paste.
public enum ClipboardItemKind: String, Codable, Sendable, CaseIterable {
  case text
  case link
  case image
  case file

  public var label: String {
    switch self {
    case .text: "Text"
    case .link: "Link"
    case .image: "Image"
    case .file: "File"
    }
  }

  /// SF Symbol used as the type icon.
  public var symbolName: String {
    switch self {
    case .text: "doc.text"
    case .link: "link"
    case .image: "photo"
    case .file: "doc"
    }
  }
}

/// How long unpinned items survive. Raw value is the number of days; `0` means forever.
public enum ClipboardRetention: Int, Codable, Sendable, CaseIterable, Identifiable {
  case oneDay = 1
  case sevenDays = 7
  case thirtyDays = 30
  case forever = 0

  public var id: Int {
    rawValue
  }

  public var label: String {
    switch self {
    case .oneDay: "1 day"
    case .sevenDays: "7 days"
    case .thirtyDays: "30 days"
    case .forever: "Forever"
    }
  }

  /// Oldest `copiedAt` that is still kept, or `nil` when nothing expires.
  public func cutoff(now: Date) -> Date? {
    guard self != .forever else {
      return nil
    }
    return now.addingTimeInterval(-Double(rawValue) * 86400)
  }

  public init(days: Int) {
    self = ClipboardRetention(rawValue: days) ?? .thirtyDays
  }
}

/// What Return does on a history item.
public enum ClipboardPasteBehavior: String, Codable, Sendable, CaseIterable, Identifiable {
  /// Write the item to the pasteboard, then send Cmd+V to the frontmost app.
  case paste
  /// Write the item to the pasteboard and stop.
  case copy

  public var id: String {
    rawValue
  }

  public var label: String {
    switch self {
    case .paste: "Paste into the frontmost app"
    case .copy: "Copy to the clipboard only"
    }
  }
}

/// Everything the clipboard feature needs from user settings. The app builds
/// this from `SettingsStore`; the module never reads `UserDefaults` itself.
public struct ClipboardSettings: Equatable, Sendable {
  public static let defaultExcludedBundleIDs = [
    "com.1password.1password",
    "com.agilebits.onepassword7",
    "com.bitwarden.desktop",
    "com.apple.keychainaccess",
    "org.keepassxc.keepassxc"
  ]

  public static let defaultMaxItems = 500
  public static let maxItemsRange = 50 ... 5000

  public var isEnabled: Bool
  public var retention: ClipboardRetention
  public var maxItems: Int
  public var excludedBundleIDs: [String]
  public var pasteBehavior: ClipboardPasteBehavior

  public init(
    isEnabled: Bool = true,
    retention: ClipboardRetention = .thirtyDays,
    maxItems: Int = ClipboardSettings.defaultMaxItems,
    excludedBundleIDs: [String] = ClipboardSettings.defaultExcludedBundleIDs,
    pasteBehavior: ClipboardPasteBehavior = .paste
  ) {
    self.isEnabled = isEnabled
    self.retention = retention
    self.maxItems = maxItems
    self.excludedBundleIDs = excludedBundleIDs
    self.pasteBehavior = pasteBehavior
  }

  public func isExcluded(bundleID: String?) -> Bool {
    guard let bundleID, !bundleID.isEmpty else {
      return false
    }
    return excludedBundleIDs.contains { $0.caseInsensitiveCompare(bundleID) == .orderedSame }
  }
}

/// One history entry. Large payloads (images, RTF, long text) live in blob files
/// next to the index; the item only carries what search and the list need.
public struct ClipboardItem: Codable, Identifiable, Hashable, Sendable {
  /// Text longer than this is kept inline only up to this many characters; the
  /// full text is stored as a blob and reloaded for paste.
  public static let inlineTextLimit = 16384

  public let id: UUID
  public var kind: ClipboardItemKind
  public var createdAt: Date
  public var copiedAt: Date
  public var isPinned: Bool
  public var sourceBundleID: String?
  public var sourceAppName: String?
  /// Plain text (full when it fits, otherwise the head; see `isTextTruncated`).
  public var text: String?
  public var isTextTruncated: Bool
  public var hasRichText: Bool
  public var hasImage: Bool
  public var imageWidth: Int?
  public var imageHeight: Int?
  public var filePaths: [String]
  /// Approximate bytes on disk (inline text + blobs).
  public var byteCount: Int
  /// Stable digest of the primary content used for de-duplication.
  public var contentHash: String

  public init(
    id: UUID = UUID(),
    kind: ClipboardItemKind,
    createdAt: Date = Date(),
    copiedAt: Date? = nil,
    isPinned: Bool = false,
    sourceBundleID: String? = nil,
    sourceAppName: String? = nil,
    text: String? = nil,
    isTextTruncated: Bool = false,
    hasRichText: Bool = false,
    hasImage: Bool = false,
    imageWidth: Int? = nil,
    imageHeight: Int? = nil,
    filePaths: [String] = [],
    byteCount: Int = 0,
    contentHash: String
  ) {
    self.id = id
    self.kind = kind
    self.createdAt = createdAt
    self.copiedAt = copiedAt ?? createdAt
    self.isPinned = isPinned
    self.sourceBundleID = sourceBundleID
    self.sourceAppName = sourceAppName
    self.text = text
    self.isTextTruncated = isTextTruncated
    self.hasRichText = hasRichText
    self.hasImage = hasImage
    self.imageWidth = imageWidth
    self.imageHeight = imageHeight
    self.filePaths = filePaths
    self.byteCount = byteCount
    self.contentHash = contentHash
  }

  /// Convenience for text and link items; picks the kind and hash automatically.
  public static func text(
    _ text: String,
    id: UUID = UUID(),
    at date: Date = Date(),
    isPinned: Bool = false,
    sourceBundleID: String? = nil,
    sourceAppName: String? = nil,
    hasRichText: Bool = false
  ) -> ClipboardItem {
    let truncated = text.count > inlineTextLimit
    let inline = truncated ? String(text.prefix(inlineTextLimit)) : text
    return ClipboardItem(
      id: id,
      kind: ClipboardContent.isLink(text) ? .link : .text,
      createdAt: date,
      isPinned: isPinned,
      sourceBundleID: sourceBundleID,
      sourceAppName: sourceAppName,
      text: inline,
      isTextTruncated: truncated,
      hasRichText: hasRichText,
      byteCount: text.utf8.count,
      contentHash: ClipboardContent.hash(text: text)
    )
  }

  /// One-line label for lists.
  public var title: String {
    switch kind {
    case .text, .link:
      return ClipboardContent.firstLine(of: text ?? "", limit: 120)
    case .image:
      return "Image"
    case .file:
      if filePaths.count == 1, let first = filePaths.first {
        return URL(fileURLWithPath: first).lastPathComponent
      }
      return "\(filePaths.count) files"
    }
  }

  /// Secondary line for lists and the preview header.
  public var subtitle: String {
    switch kind {
    case .text:
      let count = text?.count ?? 0
      let lines = text?.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).count ?? 0
      var parts = ["\(count)\(isTextTruncated ? "+" : "") characters"]
      if lines > 1 {
        parts.append("\(lines) lines")
      }
      return parts.joined(separator: ", ")
    case .link:
      if let text, let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)), let host = url.host {
        return host
      }
      return "Link"
    case .image:
      if let imageWidth, let imageHeight {
        return "\(imageWidth) × \(imageHeight) px"
      }
      return "PNG"
    case .file:
      if filePaths.count == 1, let first = filePaths.first {
        return URL(fileURLWithPath: first).deletingLastPathComponent().path
      }
      return filePaths.map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: ", ")
    }
  }

  /// Everything search may look at besides the title.
  public var searchableBody: String {
    switch kind {
    case .text, .link:
      text ?? ""
    case .image:
      ""
    case .file:
      filePaths.joined(separator: "\n")
    }
  }
}

/// Helpers shared by capture, models, and tests.
public enum ClipboardContent: Sendable {
  private static let linkSchemes: Set<String> = ["http", "https", "ftp"]

  /// True for a single-line `http(s)`/`ftp` URL with a host.
  public static func isLink(_ text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else {
      return false
    }
    guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), let host = url.host else {
      return false
    }
    return linkSchemes.contains(scheme) && !host.isEmpty
  }

  /// First non-blank line, whitespace collapsed, cut at `limit` characters.
  public static func firstLine(of text: String, limit: Int) -> String {
    let line = text
      .split(omittingEmptySubsequences: true, whereSeparator: \.isNewline)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .first { !$0.isEmpty } ?? ""
    let collapsed = line.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    if collapsed.count > limit {
      return String(collapsed.prefix(limit)) + "…"
    }
    return collapsed
  }

  public static func hash(text: String) -> String {
    "t:" + fnv1a(text.utf8)
  }

  public static func hash(imageData: Data) -> String {
    "i:" + imageData.withUnsafeBytes { fnv1a($0) }
  }

  public static func hash(filePaths: [String]) -> String {
    "f:" + fnv1a(filePaths.sorted().joined(separator: "\u{0}").utf8)
  }

  /// FNV-1a 64-bit. Stable across launches, unlike `Hasher`.
  static func fnv1a(_ bytes: some Sequence<UInt8>) -> String {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in bytes {
      hash ^= UInt64(byte)
      hash = hash &* 0x0000_0100_0000_01b3
    }
    return String(hash, radix: 16)
  }
}
