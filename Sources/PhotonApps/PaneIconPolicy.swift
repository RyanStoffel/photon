import Foundation
import PhotonCore

/// Decides where a System Settings pane's icon comes from.
///
/// Legacy `.prefPane` bundles declare their icon with `NSPrefPaneIconFile` or
/// `CFBundleIconFile` (a file under `Contents/Resources`) or `CFBundleIconName`
/// (an entry in the bundle's asset catalog). `NSWorkspace.icon(forFile:)` does not
/// know the pane-specific key and returns the generic pane document icon when it
/// finds nothing, so the policy resolves the declared icon itself and falls back
/// to the System Settings app icon when a pane declares nothing usable.
public enum PaneIconPolicy {
  public static let systemSettingsBundleID = "com.apple.systempreferences"
  public static let systemSettingsIcon = CommandIcon.application(bundleIdentifier: systemSettingsBundleID)

  static let declaredFileKeys = ["NSPrefPaneIconFile", "CFBundleIconFile"]
  static let imageExtensions = ["icns", "png", "tiff", "tif"]

  /// `info` is the pane's Info.plist; `fileExists` is injected so the rule can be tested.
  public static func icon(
    forPaneAt paneURL: URL,
    info: [String: Any],
    fileExists: (String) -> Bool
  ) -> CommandIcon {
    let resources = paneURL.appendingPathComponent("Contents/Resources", isDirectory: true)
    let declared = declaredNames(in: info)

    for name in declared {
      for candidate in candidateFileNames(for: name) {
        let path = resources.appendingPathComponent(candidate).path
        if fileExists(path) {
          return .imageFile(path: path)
        }
      }
    }

    let catalogNames = declared + [info["CFBundleIconName"] as? String].compactMap { $0 }
    if let name = catalogNames.first, fileExists(resources.appendingPathComponent("Assets.car").path) {
      return .bundleResource(bundlePath: paneURL.path, name: (name as NSString).deletingPathExtension)
    }
    return systemSettingsIcon
  }

  /// Non-empty `NSPrefPaneIconFile` / `CFBundleIconFile` values, in that order.
  static func declaredNames(in info: [String: Any]) -> [String] {
    declaredFileKeys.compactMap { key in
      guard let value = info[key] as? String else {
        return nil
      }
      let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? nil : trimmed
    }
  }

  /// `"Network"` → `Network.icns`, `Network.png`, ...; `"Network.icns"` → itself only.
  public static func candidateFileNames(for declaredName: String) -> [String] {
    let ext = (declaredName as NSString).pathExtension.lowercased()
    if imageExtensions.contains(ext) {
      return [declaredName]
    }
    var names = [declaredName]
    names += imageExtensions.map { "\(declaredName).\($0)" }
    return names
  }
}
