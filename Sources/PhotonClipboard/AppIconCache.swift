#if canImport(AppKit)
import AppKit
import UniformTypeIdentifiers

/// Resolves and caches source-app icons by bundle identifier for list rows.
@MainActor
public final class AppIconCache {
  public static let shared = AppIconCache()

  private var icons: [String: NSImage] = [:]
  private lazy var genericIcon: NSImage = NSWorkspace.shared.icon(for: .applicationBundle)

  private init() {}

  public func icon(forBundleID bundleID: String?) -> NSImage {
    guard let bundleID, !bundleID.isEmpty else {
      return genericIcon
    }
    if let cached = icons[bundleID] {
      return cached
    }
    let icon: NSImage = if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
      NSWorkspace.shared.icon(forFile: url.path)
    } else {
      genericIcon
    }
    icons[bundleID] = icon
    return icon
  }

  /// Display name for a bundle id, falling back to the id itself.
  public func appName(forBundleID bundleID: String) -> String {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
      return bundleID
    }
    if let bundle = Bundle(url: url) {
      if let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, !name.isEmpty {
        return name
      }
      if let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String, !name.isEmpty {
        return name
      }
    }
    return url.deletingPathExtension().lastPathComponent
  }
}
#endif
