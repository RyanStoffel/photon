/// Where the launcher finds the picture for a `Command`.
///
/// Providers describe the icon; the app resolves and caches the actual image.
/// Keeping this a value keeps `Command` `Sendable` and `PhotonCore` free of AppKit.
public enum CommandIcon: Hashable, Sendable {
  /// The Finder icon of the file or bundle at `path` (`NSWorkspace.icon(forFile:)`).
  case fileIcon(path: String)
  /// An image file on disk (`.icns`, `.png`, `.tiff`) loaded as-is.
  case imageFile(path: String)
  /// The icon of the installed application with this bundle identifier.
  case application(bundleIdentifier: String)
  /// A named image inside a bundle, including its asset catalog (`Bundle.image(forResource:)`).
  case bundleResource(bundlePath: String, name: String)
  /// An SF Symbol, rendered as a template glyph.
  case symbol(name: String)
}
