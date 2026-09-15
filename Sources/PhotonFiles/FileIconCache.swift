import AppKit

/// Finder icons keyed by path. Results are prefetched on a background thread
/// right after ranking, so rows render with their icon on first draw.
public final class FileIconCache: @unchecked Sendable {
  public static let shared = FileIconCache()

  private let cache = NSCache<NSString, NSImage>()

  init() {
    cache.countLimit = 600
  }

  public func icon(for file: FileResult) -> NSImage {
    icon(forPath: file.path)
  }

  public func icon(forPath path: String) -> NSImage {
    let key = path as NSString
    if let cached = cache.object(forKey: key) {
      return cached
    }
    let image = NSWorkspace.shared.icon(forFile: path)
    cache.setObject(image, forKey: key)
    return image
  }

  public func prefetch(_ files: [FileResult]) {
    for file in files {
      _ = icon(forPath: file.path)
    }
  }
}
