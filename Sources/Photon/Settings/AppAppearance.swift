import AppKit

/// Settings > Appearance: follow the system or force light / dark for every Photon window.
enum AppAppearance: String, CaseIterable, Identifiable {
  case system
  case light
  case dark

  var id: String {
    rawValue
  }

  var title: String {
    switch self {
    case .system: "System"
    case .light: "Light"
    case .dark: "Dark"
    }
  }

  /// `nil` means inherit the system appearance.
  var nsAppearance: NSAppearance? {
    switch self {
    case .system: nil
    case .light: NSAppearance(named: .aqua)
    case .dark: NSAppearance(named: .darkAqua)
    }
  }
}
