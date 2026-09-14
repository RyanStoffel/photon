import Foundation

/// Deterministic UI states for automated screenshots. Inert unless `PHOTON_UI_SCENARIO` or
/// `--ui-scenario` is set at launch.
enum UIScenario: Equatable, Sendable {
  case launcherEmpty
  case launcherQuery(String)
  case clipboardEmpty
  case filesEmpty
  case filesQuery(String)
  case settings(SettingsPaneID)
  case notes

  static var current: UIScenario? {
    if let fromEnv = ProcessInfo.processInfo.environment["PHOTON_UI_SCENARIO"], !fromEnv.isEmpty {
      return parse(fromEnv)
    }
    let args = ProcessInfo.processInfo.arguments
    if let index = args.firstIndex(of: "--ui-scenario"), index + 1 < args.count {
      return parse(args[index + 1])
    }
    return nil
  }

  var isActive: Bool {
    Self.current != nil
  }

  /// Isolated Application Support root (`PHOTON_ISOLATED_DATA_ROOT`).
  static var isolatedDataRoot: URL? {
    guard current != nil else {
      return nil
    }
    guard let path = ProcessInfo.processInfo.environment["PHOTON_ISOLATED_DATA_ROOT"], !path.isEmpty else {
      return nil
    }
    return URL(fileURLWithPath: path, isDirectory: true)
  }

  /// When set, the app writes `ready` here once the scenario UI has settled.
  static var readyMarkerURL: URL? {
    guard let path = ProcessInfo.processInfo.environment["PHOTON_UI_SCENARIO_READY_PATH"], !path.isEmpty else {
      return nil
    }
    return URL(fileURLWithPath: path)
  }

  /// When set, the app writes the `CGWindow` number to capture for this scenario.
  static var windowIDMarkerURL: URL? {
    guard let path = ProcessInfo.processInfo.environment["PHOTON_UI_SCENARIO_WINDOW_ID_PATH"], !path.isEmpty else {
      return nil
    }
    return URL(fileURLWithPath: path)
  }

  private static func parse(_ raw: String) -> UIScenario? {
    if raw == "launcher-empty" {
      return .launcherEmpty
    }
    if raw.hasPrefix("launcher-query:") {
      let query = String(raw.dropFirst("launcher-query:".count))
      return .launcherQuery(query)
    }
    if raw == "clipboard-empty" {
      return .clipboardEmpty
    }
    if raw == "files-empty" {
      return .filesEmpty
    }
    if raw.hasPrefix("files-query:") {
      let query = String(raw.dropFirst("files-query:".count))
      return .filesQuery(query)
    }
    if raw.hasPrefix("settings:") {
      let pane = String(raw.dropFirst("settings:".count))
      guard let id = SettingsPaneID(rawValue: pane) else {
        return nil
      }
      return .settings(id)
    }
    if raw == "notes" {
      return .notes
    }
    if raw == "calculator" {
      return .launcherQuery("2 + 2")
    }
    return nil
  }
}

enum SettingsPaneID: String, Hashable, Sendable {
  case general
  case appearance
  case clipboard
  case notes
  case files
  case keybinds
  case about
}
