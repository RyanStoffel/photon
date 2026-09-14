import Foundation

/// Where Spotlight looks. Raw values match what `SettingsStore` persists.
public enum FileSearchScope: String, CaseIterable, Sendable {
  case home
  case computer = "this-mac"

  public var title: String {
    switch self {
    case .home: "Home folder"
    case .computer: "This Mac"
    }
  }
}

/// What Enter does on a file result. Cmd+Enter performs the other one.
public enum FileDefaultAction: String, CaseIterable, Sendable {
  case open
  case reveal

  public var title: String {
    switch self {
    case .open: "Open"
    case .reveal: "Reveal in Finder"
    }
  }

  public var other: FileDefaultAction {
    self == .open ? .reveal : .open
  }
}

/// Everything the Files feature reads from user settings. Value type so it can
/// be handed to background work without locking.
public struct FileSearchSettings: Equatable, Sendable {
  public static let defaultMaxResults = 50
  public static let maxResultsRange = 10 ... 200
  public static let inlineLimit = 3
  public static let inlineMinimumQueryLength = 3

  public var scope: FileSearchScope
  /// Extra folders searched in addition to the scope (external volumes, for example).
  public var extraFolders: [String]
  /// Folders whose contents never appear in results. Spotlight privacy
  /// exclusions are applied by Spotlight itself and need no entry here.
  public var excludedFolders: [String]
  public var searchContents: Bool
  public var maxResults: Int
  public var defaultAction: FileDefaultAction
  public var inlineResults: Bool

  public init(
    scope: FileSearchScope = .computer,
    extraFolders: [String] = [],
    excludedFolders: [String] = [],
    searchContents: Bool = false,
    maxResults: Int = FileSearchSettings.defaultMaxResults,
    defaultAction: FileDefaultAction = .open,
    inlineResults: Bool = true
  ) {
    self.scope = scope
    self.extraFolders = extraFolders
    self.excludedFolders = excludedFolders
    self.searchContents = searchContents
    self.maxResults = maxResults
    self.defaultAction = defaultAction
    self.inlineResults = inlineResults
  }

  public var clampedMaxResults: Int {
    min(max(maxResults, Self.maxResultsRange.lowerBound), Self.maxResultsRange.upperBound)
  }
}
