import PhotonCore
import XCTest

final class LauncherLayoutTests: XCTestCase {
  func testWidthPresetsGrowInOrderAndDefaultToRegular() {
    let widths = LauncherPanelWidth.allCases.map(\.points)
    XCTAssertEqual(widths, widths.sorted())
    XCTAssertEqual(LauncherPanelWidth.default, .regular)
    XCTAssertEqual(LauncherPanelWidth.regular.points, 760)
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

  func testExpandedPanelLayoutsUseIdenticalOuterDimensions() {
    let width = LauncherPanelWidth.default.points
    let launcherRecommendations = LauncherPanelSize(width: width, content: .recommendations)
    let files = LauncherPanelSize(width: width, content: .fullHeight)
    let clipboard = LauncherPanelSize(width: width, content: .fullHeight)

    XCTAssertEqual(files, launcherRecommendations)
    XCTAssertEqual(clipboard, launcherRecommendations)
    XCTAssertEqual(launcherRecommendations.width, 760)
    XCTAssertEqual(launcherRecommendations.height, LauncherLayout.expandedHeight)
  }

  func testFeatureViewsUseTheSharedExpandedHeight() {
    XCTAssertEqual(LauncherLayout.height(for: .fullHeight), LauncherLayout.detailHeight)
    XCTAssertEqual(LauncherLayout.height(for: .recommendations), LauncherLayout.detailHeight)
    XCTAssertEqual(LauncherLayout.detailHeight, LauncherLayout.maxHeight)
    XCTAssertGreaterThan(LauncherLayout.expandedHeight, 422)
    XCTAssertGreaterThan(LauncherLayout.detailWidth, LauncherPanelWidth.wide.points)
  }

  func testExpandedSplitFitsInsideTheCompactLauncherWidth() {
    XCTAssertLessThan(LauncherLayout.detailListWidth, LauncherPanelWidth.compact.points)
    XCTAssertGreaterThan(LauncherLayout.detailListWidth, LauncherLayout.iconSize * 4)
    for width in LauncherPanelWidth.allCases.map(\.points) {
      XCTAssertGreaterThan(width - LauncherLayout.detailListWidth, 300)
    }
  }

  func testSuggestionsFitOnOnePage() {
    XCTAssertEqual(LauncherLayout.suggestionCount, LauncherLayout.maxVisibleRows)
    XCTAssertEqual(
      LauncherLayout.height(
        for: .rows(count: LauncherLayout.suggestionCount, showsCalculatorHero: false)
      ),
      LauncherLayout.expandedHeight
    )
  }

  func testCalculatorHeroReplacesFirstRowHeight() {
    let rowOnly = LauncherLayout.listHeight(rowCount: 1)
    let heroOnly = LauncherLayout.listHeight(rowCount: 1, showsCalculatorHero: true)
    XCTAssertGreaterThan(heroOnly, rowOnly)

    let heroPlusOne = LauncherLayout.listHeight(rowCount: 2, showsCalculatorHero: true)
    XCTAssertEqual(heroPlusOne - heroOnly, LauncherLayout.rowHeight + 2 * LauncherLayout.listInset)
  }

  func testDetailMetadataReservesFooterSafeInset() {
    XCTAssertGreaterThan(LauncherLayout.detailFooterSafeInset, 0)
    XCTAssertGreaterThan(LauncherLayout.detailMetadataHeight, 120)
    XCTAssertLessThan(
      LauncherLayout.detailMetadataHeight + LauncherLayout.detailFooterSafeInset,
      LauncherLayout.expandedListHeight / 2
    )
    XCTAssertGreaterThan(LauncherLayout.panelDragSlop, 0)
    XCTAssertLessThan(LauncherLayout.panelDragSlop, LauncherLayout.rowHeight)
  }
}
