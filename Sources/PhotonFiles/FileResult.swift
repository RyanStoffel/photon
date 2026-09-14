import Foundation

/// One Spotlight hit. Plain data so it can cross threads freely.
public struct FileResult: Identifiable, Hashable, Sendable {
  public var id: String {
    path
  }

  public let path: String
  /// Finder-style name (`kMDItemDisplayName`).
  public let displayName: String
  /// On-disk name including the extension (`kMDItemFSName`).
  public let fileName: String
  /// Localized kind, for example "PDF document" or "Folder".
  public let kind: String
  public let contentType: String?
  public let isFolder: Bool
  public let isApplication: Bool
  public let size: Int64?
  public let created: Date?
  public let modified: Date?
  public let lastUsed: Date?

  public init(
    path: String,
    displayName: String,
    fileName: String,
    kind: String,
    contentType: String? = nil,
    isFolder: Bool = false,
    isApplication: Bool = false,
    size: Int64? = nil,
    created: Date? = nil,
    modified: Date? = nil,
    lastUsed: Date? = nil
  ) {
    self.path = path
    self.displayName = displayName
    self.fileName = fileName
    self.kind = kind
    self.contentType = contentType
    self.isFolder = isFolder
    self.isApplication = isApplication
    self.size = size
    self.created = created
    self.modified = modified
    self.lastUsed = lastUsed
  }

  public var url: URL {
    URL(fileURLWithPath: path, isDirectory: isFolder)
  }

  public var parentPath: String {
    (path as NSString).deletingLastPathComponent
  }

  /// Display name without its extension, used for relevance scoring.
  public var stem: String {
    let base = displayName.isEmpty ? fileName : displayName
    if isFolder {
      return base
    }
    let trimmed = (base as NSString).deletingPathExtension
    return trimmed.isEmpty ? base : trimmed
  }
}
