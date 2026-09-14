import PhotonCore
import XCTest

final class LauncherLayoutTests: XCTestCase {
  func testWidthPresetsGrowInOrderAndDefaultToRegular() {
    let widths = LauncherPanelWidth.allCases.map(\.points)
    XCTAssertEqual(widths, widths.sorted())
    XCTAssertEqual(LauncherPanelWidth.default, .regular)
    XCTAssertEqual(LauncherPanelWidth.regular.points, 740)
    XCTAssertEqual(LauncherPanelWidth(rawValue: "wide"), .wide)
  }

  func testWidthPresetTitlesAreDistinct() {
    let titles = Set(LauncherPanelWidth.allCases.map(\.title))
    XCTAssertEqual(titles.count, LauncherPanelWidth.allCases.count)
  }

  func testCompactHeightIsSearchFieldPlusFooter() {
    XCTAssertEqual(
      LauncherLayout.height(for: .searchOnly),
      LauncherLayout.searchFieldHeight + LauncherLayout.hairline + LauncherLayout.footerHeight
    )
  }

  func testListHeightShowsAtLeastOneRow() {
    XCTAssertEqual(LauncherLayout.listHeight(rowCount: 0), LauncherLayout.listHeight(rowCount: 1))
    XCTAssertEqual(LauncherLayout.height(for: .rows(0)), LauncherLayout.height(for: .rows(1)))
  }

  func testListHeightGrowsPerRowUntilThePageIsFull() {
    let one = LauncherLayout.height(for: .rows(1))
    let three = LauncherLayout.height(for: .rows(3))
    XCTAssertEqual(three - one, 2 * LauncherLayout.rowHeight)

    let full = LauncherLayout.height(for: .rows(LauncherLayout.maxVisibleRows))
    XCTAssertEqual(LauncherLayout.height(for: .rows(200)), full)
    XCTAssertEqual(LauncherLayout.maxHeight, full)
  }

  func testFeatureViewsUseTheFullHeight() {
    XCTAssertEqual(LauncherLayout.height(for: .fullHeight), LauncherLayout.maxHeight)
    XCTAssertGreaterThan(LauncherLayout.maxHeight, LauncherLayout.compactHeight)
  }

  func testSuggestionsFitOnOnePage() {
    XCTAssertLessThanOrEqual(LauncherLayout.suggestionCount, LauncherLayout.maxVisibleRows)
  }
}
