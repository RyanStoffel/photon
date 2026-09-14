import Foundation

/// Human-readable titles and searchable aliases for legacy `.prefPane` bundles.
public enum SystemSettingsPaneMetadata: Sendable {
  /// Resolves the title shown in the launcher, preferring localized bundle metadata.
  public static func displayName(
    info: [String: Any],
    localizedInfo: [String: Any]?,
    fallbackStem: String
  ) -> String {
    for source in [localizedInfo, info].compactMap(\.self) {
      if let name = bundleName(in: source), !name.isEmpty {
        return name
      }
    }
    if let known = knownTitles[fallbackStem] {
      return known
    }
    return humanizeStem(fallbackStem)
  }

  /// Extra terms for fuzzy search (aliases and stable identifiers). Does not affect the row title.
  public static func searchKeywords(
    displayName: String,
    bundleIdentifier: String,
    fallbackStem: String
  ) -> [String] {
    var terms = Set<String>()
    terms.insert(bundleIdentifier)
    terms.insert(fallbackStem)
    terms.insert(displayName)

    let idLower = bundleIdentifier.lowercased()
    let stemLower = fallbackStem.lowercased()
    for (key, aliases) in aliasTable {
      let keyLower = key.lowercased()
      if idLower.contains(keyLower) || stemLower.contains(keyLower) {
        for alias in aliases {
          terms.insert(alias)
        }
      }
    }
    return Array(terms)
  }

  private static func bundleName(in info: [String: Any]) -> String? {
    if let name = info["CFBundleDisplayName"] as? String, !name.isEmpty {
      return name
    }
    if let name = info["CFBundleName"] as? String, !name.isEmpty {
      return name
    }
    return nil
  }

  /// Titles when bundles ship without usable plist keys (common for system panes).
  private static let knownTitles: [String: String] = [
    "AppleIDPref": "Apple ID",
    "AppearancePref": "Appearance",
    "BatteryPref": "Battery",
    "BluetoothPref": "Bluetooth",
    "CDsAndDVDsPref": "CDs & DVDs",
    "ClassroomSettingsPref": "Classroom",
    "DateAndTimePref": "Date & Time",
    "DesktopScreenEffectsPref": "Wallpaper",
    "DesktopScreenSaverPref": "Wallpaper",
    "DisplaysPref": "Displays",
    "DockPref": "Desktop & Dock",
    "EnergySaverPref": "Battery",
    "FamilyControlsPref": "Family",
    "GameControllerPref": "Game Controller",
    "InternetAccountsPref": "Internet Accounts",
    "KeyboardPref": "Keyboard",
    "LocalizationPref": "Language & Region",
    "MousePref": "Mouse",
    "NetworkPref": "Network",
    "NotificationsPref": "Notifications",
    "ParentalControlsPref": "Screen Time",
    "PasswordsPref": "Passwords",
    "PrintScanPref": "Printers & Scanners",
    "ProfilesPref": "Profiles",
    "SecurityPref": "Privacy & Security",
    "SharingPref": "Sharing",
    "SoftwareUpdatePref": "Software Update",
    "SoundPref": "Sound",
    "SpotlightPref": "Spotlight",
    "StartupDiskPref": "Startup Disk",
    "TimeMachinePref": "Time Machine",
    "TrackpadPref": "Trackpad",
    "UniversalAccessPref": "Accessibility",
    "UsersPref": "Users & Groups",
    "WalletPref": "Wallet & Apple Pay",
    "XsanPref": "Xsan",
  ]

  /// Maps bundle-id fragments or `.prefPane` stems to extra search terms.
  private static let aliasTable: [String: [String]] = [
    "desktopscreen": ["wallpaper", "background", "screen saver", "screensaver"],
    "wallpaper": ["wallpaper", "background"],
    "security": ["privacy", "privacy & security", "security"],
    "energysaver": ["battery", "power", "energy"],
    "batterypref": ["battery", "power"],
    "bluetooth": ["bluetooth"],
    "network": ["network", "wifi", "wi-fi", "ethernet"],
    "sound": ["sound", "volume", "audio"],
    "displays": ["display", "monitor", "screen"],
    "keyboard": ["keyboard"],
    "trackpad": ["trackpad"],
    "mouse": ["mouse"],
    "spotlight": ["spotlight", "search"],
    "softwareupdate": ["update", "updates", "software update"],
    "sharing": ["sharing", "airdrop"],
    "universalaccess": ["accessibility", "a11y"],
    "users": ["users", "groups", "login"],
    "timemachine": ["backup", "time machine"],
    "notifications": ["notifications", "alerts"],
    "internetaccounts": ["accounts", "mail", "icloud"],
    "appleid": ["apple id", "icloud account"],
    "passwords": ["passwords", "passkeys"],
    "wallet": ["wallet", "apple pay"],
    "appearance": ["appearance", "theme", "dark mode", "light mode"],
    "dock": ["dock", "desktop"],
    "localization": ["language", "region"],
    "parentalcontrols": ["screen time", "parental"],
    "familycontrols": ["family"],
    "gamecontroller": ["controller", "gamepad"],
    "print": ["printer", "printers", "scanner"],
    "startupdisk": ["startup", "boot"],
    "dateandtime": ["date", "time", "clock"],
  ]

  private static func humanizeStem(_ stem: String) -> String {
    var text = stem
    if text.hasSuffix("Pref") {
      text = String(text.dropLast(4))
    }
    var words: [String] = []
    var current = ""
    for character in text {
      if character.isUppercase, !current.isEmpty {
        words.append(current)
        current = String(character)
      } else {
        current.append(character)
      }
    }
    if !current.isEmpty {
      words.append(current)
    }
    return words.joined(separator: " ")
  }
}
