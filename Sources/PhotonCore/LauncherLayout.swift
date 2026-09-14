import Foundation

/// User-selectable launcher panel width.
public enum LauncherPanelWidth: String, CaseIterable, Codable, Sendable, Identifiable {
  case compact
  case regular
  case wide

  public static let `default` = LauncherPanelWidth.regular

  public var id: String {
    rawValue
  }

  public var title: String {
    switch self {
    case .compact: "Compact"
    case .regular: "Regular"
    case .wide: "Wide"
    }
  }

  public var points: Double {
    switch self {
    case .compact: 620
    case .regular: 740
    case .wide: 860
    }
  }
}

/// What the launcher panel shows below the search field.
public enum LauncherContent: Equatable, Sendable {
  /// Empty query in compact mode: search field and footer only.
  case searchOnly
  /// The command list. `0` rows still shows one line (indexing or no results).
  case rows(Int)
  /// A feature view with its own layout (clipboard history, file search).
  case fullHeight
}

/// Fixed metrics of the launcher panel. Heights are derived here so the
/// AppKit window and the SwiftUI content always agree on the panel size.
public enum LauncherLayout {
  public static let searchFieldHeight: Double = 56
  public static let footerHeight: Double = 32
  public static let rowHeight: Double = 40
  /// Padding above the first and below the last row.
  public static let listInset: Double = 6
  public static let maxVisibleRows = 8
  /// Rows shown for an empty query when suggestions are enabled.
  public static let suggestionCount = 8
  public static let hairline: Double = 1
  public static let cornerRadius: Double = 12
  public static let iconSize: Double = 28

  /// Height of the list area for `count` rows, clamped to `maxVisibleRows` and never below one row.
  public static func listHeight(rowCount count: Int) -> Double {
    let visible = min(max(count, 1), maxVisibleRows)
    return Double(visible) * rowHeight + 2 * listInset
  }

  /// Search field and footer with a hairline between them.
  public static var compactHeight: Double {
    searchFieldHeight + hairline + footerHeight
  }

  /// Tallest the panel gets: a full page of rows.
  public static var maxHeight: Double {
    height(for: .rows(maxVisibleRows))
  }

  public static func height(for content: LauncherContent) -> Double {
    switch content {
    case .searchOnly:
      compactHeight
    case let .rows(count):
      searchFieldHeight + hairline + listHeight(rowCount: count) + hairline + footerHeight
    case .fullHeight:
      maxHeight
    }
  }
}
