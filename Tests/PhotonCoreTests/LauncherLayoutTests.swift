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
    XCTAssertEqual(
      LauncherLayout.height(for: .rows(count: 0, showsCalculatorHero: false)),
      LauncherLayout.height(for: .rows(count: 1, showsCalculatorHero: false))
    )
  }

  func testListHeightGrowsPerRowUntilThePageIsFull() {
    let one = LauncherLayout.height(for: .rows(count: 1, showsCalculatorHero: false))
    let three = LauncherLayout.height(for: .rows(count: 3, showsCalculatorHero: false))
    XCTAssertEqual(three - one, 2 * LauncherLayout.rowHeight)

    let full = LauncherLayout.height(for: .rows(count: LauncherLayout.maxVisibleRows, showsCalculatorHero: false))
    XCTAssertEqual(LauncherLayout.height(for: .rows(count: 200, showsCalculatorHero: false)), full)
    XCTAssertEqual(LauncherLayout.maxHeight, full)
  }

  func testFeatureViewsUseTheFullHeight() {
    XCTAssertEqual(LauncherLayout.height(for: .fullHeight), LauncherLayout.detailHeight)
    XCTAssertGreaterThan(LauncherLayout.detailHeight, LauncherLayout.maxHeight)
    XCTAssertGreaterThan(LauncherLayout.detailWidth, LauncherPanelWidth.wide.points)
  }

  func testSuggestionsFitOnOnePage() {
    XCTAssertLessThanOrEqual(LauncherLayout.suggestionCount, LauncherLayout.maxVisibleRows)
  }

  func testCalculatorHeroReplacesFirstRowHeight() {
    let rowOnly = LauncherLayout.listHeight(rowCount: 1)
    let heroOnly = LauncherLayout.listHeight(rowCount: 1, showsCalculatorHero: true)
    XCTAssertGreaterThan(heroOnly, rowOnly)

    let heroPlusOne = LauncherLayout.listHeight(rowCount: 2, showsCalculatorHero: true)
    XCTAssertEqual(heroPlusOne - heroOnly, LauncherLayout.rowHeight + 2 * LauncherLayout.listInset)
  }
}
