import PhotonCore
import XCTest

final class SelectionNavigationTests: XCTestCase {
  func testMovingClampsInsteadOfWrapping() {
    XCTAssertEqual(SelectionNavigation.moving(from: 0, by: -1, count: 30), 0)
    XCTAssertEqual(SelectionNavigation.moving(from: 29, by: 1, count: 30), 29)
    XCTAssertEqual(SelectionNavigation.moving(from: 0, by: 1, count: 30), 1)
  }

  func testDownOnTheLastVisibleRowAdvancesIntoTheCatalog() {
    let visible = SelectionNavigation.visibleRowCount(
      listHeight: LauncherLayout.expandedListHeight,
      rowHeight: LauncherLayout.rowHeight,
      inset: LauncherLayout.listInset
    )
    XCTAssertEqual(visible, LauncherLayout.visibleRecommendationRows)
    XCTAssertGreaterThan(visible, 1)

    let lastVisible = visible - 1
    let next = SelectionNavigation.moving(from: lastVisible, by: 1, count: 30)
    XCTAssertEqual(next, visible, "Down at the last on-screen row must scroll, not wrap to 0")
    XCTAssertNotEqual(next, 0)
  }

  func testOnePageCatalogStopsAtTheLastItem() {
    let visible = LauncherLayout.visibleRecommendationRows
    let last = SelectionNavigation.moving(from: visible - 1, by: 1, count: visible)
    XCTAssertEqual(last, visible - 1)
  }

  func testEmptyListStaysAtZero() {
    XCTAssertEqual(SelectionNavigation.moving(from: 0, by: 1, count: 0), 0)
  }
}
