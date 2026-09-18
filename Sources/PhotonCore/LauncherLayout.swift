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
    case .regular: 760
    case .wide: 860
    }
  }
}

/// What the launcher panel shows below the search field.
public enum LauncherContent: Equatable, Sendable {
  /// Empty query in compact mode: search field and footer only.
  case searchOnly
  /// Empty-query recommendations revealed by pressing Down.
  case recommendations
  /// The command list. `0` rows still shows one line (indexing or no results).
  /// When `showsCalculatorHero` is true, the first result is rendered as a calculator card instead of a row.
  case rows(count: Int, showsCalculatorHero: Bool)
  /// A feature view with its own layout (clipboard history, file search).
  case fullHeight
}

/// Fixed metrics of the launcher panel. Heights are derived here so the
/// AppKit window and the SwiftUI content always agree on the panel size.
public enum LauncherLayout {
  public static let searchFieldHeight: Double = 56
  public static let footerHeight: Double = 32
  /// Bottom padding inside the Files/clipboard detail pane so metadata cannot
  /// paint over the command footer.
  public static let detailFooterSafeInset: Double = 10
  /// Metadata / Information block height, excluding the footer-safe inset.
  public static let detailMetadataHeight: Double = 156
  /// Movement before a panel-wide mouse-down becomes a window drag, so clicks
  /// still select rows and activate footer buttons.
  public static let panelDragSlop: Double = 6
  public static let rowHeight: Double = 40
  /// Padding above the first and below the last row.
  public static let listInset: Double = 6
  public static let maxVisibleRows = 10
  /// Rows shown for an empty query when suggestions are enabled.
  public static let suggestionCount = maxVisibleRows
  /// Empty-query recommendations list the full catalog (apps, recs, shortcuts), not one page.
  public static let recommendationCatalogLimit = 250
  /// Fully visible rows in the expanded recommendations list.
  public static var visibleRecommendationRows: Int {
    SelectionNavigation.visibleRowCount(
      listHeight: expandedListHeight,
      rowHeight: rowHeight,
      inset: listInset
    )
  }

  public static let hairline: Double = 1
  public static let cornerRadius: Double = 12
  public static let iconSize: Double = 28
  /// Legacy wide-panel metric. Expanded Files/clipboard keep `panelWidth` and
  /// split list/preview horizontally inside `detailListWidth` instead.
  public static let detailWidth: Double = 980
  /// Shared launcher-recommendations, Files, and clipboard panel height.
  public static let expandedHeight: Double = 502
  public static let expandedListHeight = expandedHeight - searchFieldHeight - footerHeight - 2 * hairline
  public static let detailHeight = expandedHeight
  /// Left-hand results column inside an expanded Files or clipboard panel.
  public static let detailListWidth: Double = 268
  /// Raycast-style calculator hero card (section label + split card).
  public static let calculatorSectionSpacing: Double = 8
  public static let calculatorCardHeight: Double = 108
  public static let calculatorSectionHeaderHeight: Double = 18

  /// Height of the list area for `count` rows, clamped to `maxVisibleRows` and never below one row.
  public static func listHeight(rowCount count: Int, showsCalculatorHero: Bool = false) -> Double {
    let heroHeight = showsCalculatorHero
      ? calculatorSectionHeaderHeight + calculatorSectionSpacing + calculatorCardHeight + listInset
      : 0
    let dataRows = showsCalculatorHero ? max(count - 1, 0) : count
    if showsCalculatorHero, dataRows == 0 {
      return heroHeight
    }
    let visible = min(max(dataRows, 1), maxVisibleRows)
    return heroHeight + Double(visible) * rowHeight + 2 * listInset
  }

  /// Search field and footer with a hairline between them.
  public static var compactHeight: Double {
    searchFieldHeight + hairline + footerHeight
  }

  /// Tallest the panel gets: a full page of rows.
  public static var maxHeight: Double {
    expandedHeight
  }

  public static func height(for content: LauncherContent) -> Double {
    switch content {
    case .searchOnly:
      compactHeight
    case .recommendations:
      expandedHeight
    case let .rows(count: count, showsCalculatorHero: showsCalculatorHero):
      searchFieldHeight + hairline + listHeight(rowCount: count, showsCalculatorHero: showsCalculatorHero)
        + hairline + footerHeight
    case .fullHeight:
      detailHeight
    }
  }
}

/// Framework-neutral dimensions shared by AppKit panel sizing and layout tests.
public struct LauncherPanelSize: Equatable, Sendable {
  public let width: Double
  public let height: Double

  public init(width: Double, content: LauncherContent) {
    self.width = width
    height = LauncherLayout.height(for: content)
  }
}
