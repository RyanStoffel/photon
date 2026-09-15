import AppKit
import PhotonCore

/// What the launcher draws for a command once its `CommandIcon` is resolved.
enum ResolvedCommandIcon {
  case image(NSImage)
  case symbol(String)
}

/// Turns `CommandIcon` values into images, once each.
///
/// Safe to use from any thread: `NSWorkspace.icon(forFile:)` and image loading
/// are thread-safe and `NSCache` synchronises itself, so the app index can warm
/// the cache in the background and rows still resolve synchronously on first draw.
final class CommandIconCache: @unchecked Sendable {
  static let shared = CommandIconCache()

  private let images = NSCache<NSString, NSImage>()
  private let misses = NSCache<NSString, NSNumber>()

  init() {
    images.countLimit = 1200
    misses.countLimit = 1200
  }

  /// The declared icon when it resolves, otherwise `fallbackSymbol`.
  func resolve(_ icon: CommandIcon?, fallbackSymbol: String) -> ResolvedCommandIcon {
    if let icon {
      switch icon {
      case let .symbol(name):
        if image(for: icon) != nil {
          return .symbol(name)
        }
      default:
        if let image = image(for: icon) {
          return .image(image)
        }
      }
    }
    return .symbol(fallbackSymbol)
  }

  func image(for icon: CommandIcon) -> NSImage? {
    let key = Self.key(for: icon) as NSString
    if let hit = images.object(forKey: key) {
      return hit
    }
    if misses.object(forKey: key) != nil {
      return nil
    }
    guard let image = load(icon), image.isValid else {
      misses.setObject(1, forKey: key)
      return nil
    }
    images.setObject(image, forKey: key)
    return image
  }

  func prefetch(_ icons: [CommandIcon]) {
    for icon in icons {
      _ = image(for: icon)
    }
  }

  private func load(_ icon: CommandIcon) -> NSImage? {
    switch icon {
    case let .fileIcon(path):
      guard FileManager.default.fileExists(atPath: path) else {
        return nil
      }
      return NSWorkspace.shared.icon(forFile: path)
    case let .imageFile(path):
      return NSImage(contentsOfFile: path)
    case let .application(bundleIdentifier):
      guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
        return nil
      }
      return NSWorkspace.shared.icon(forFile: url.path)
    case let .bundleResource(bundlePath, name):
      return Bundle(path: bundlePath)?.image(forResource: NSImage.Name(name))
    case let .symbol(name):
      return NSImage(systemSymbolName: name, accessibilityDescription: nil)
    }
  }

  private static func key(for icon: CommandIcon) -> String {
    switch icon {
    case let .fileIcon(path): "file:\(path)"
    case let .imageFile(path): "image:\(path)"
    case let .application(bundleIdentifier): "app:\(bundleIdentifier)"
    case let .bundleResource(bundlePath, name): "resource:\(bundlePath)#\(name)"
    case let .symbol(name): "symbol:\(name)"
    }
  }
}
