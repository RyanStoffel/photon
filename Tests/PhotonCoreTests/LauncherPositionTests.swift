import PhotonCore
import XCTest

final class LauncherPositionTests: XCTestCase {
  private let visible = ScreenVisibleFrame(minX: 0, minY: 0, width: 1440, height: 900)
  private let panel = PanelSize(width: 740, height: 89)

  func testDefaultOriginCentersHorizontally() {
    let origin = LauncherPosition.defaultOrigin(panelSize: panel, visible: visible)
    XCTAssertEqual(origin.x + panel.width / 2, visible.midX, accuracy: 0.001)
  }

  func testSnapGuidesMatchCenteredPanelEdges() {
    let guides = LauncherPosition.snapGuideXPositions(visible: visible, panelWidth: panel.width)
    XCTAssertEqual(guides.left, visible.midX - panel.width / 2)
    XCTAssertEqual(guides.right, visible.midX + panel.width / 2)
  }

  func testResolveHorizontalSnapSnapsInsideGuides() {
    let result = LauncherPosition.resolveHorizontalSnap(
      panelMidX: visible.midX,
      panelWidth: panel.width,
      visible: visible
    )
    XCTAssertTrue(result.isHorizontallyCentered)
    XCTAssertEqual(result.originX, visible.midX - panel.width / 2, accuracy: 0.001)
  }

  func testResolveHorizontalSnapKeepsOffsetOutsideGuides() {
    let offsetMidX = visible.midX + panel.width / 2 + 40
    let result = LauncherPosition.resolveHorizontalSnap(
      panelMidX: offsetMidX,
      panelWidth: panel.width,
      visible: visible
    )
    XCTAssertFalse(result.isHorizontallyCentered)
    XCTAssertEqual(result.originX, offsetMidX - panel.width / 2, accuracy: 0.001)
  }

  func testStoredPositionRecordsCenteredPlacement() {
    let origin = PanelOrigin(x: visible.midX - panel.width / 2, y: 400)
    let stored = LauncherPosition.storedPosition(origin: origin, panelWidth: panel.width, visible: visible)
    XCTAssertTrue(stored.isHorizontallyCentered)
    XCTAssertEqual(stored.originY, 400, accuracy: 0.001)
  }

  func testClampingKeepsPanelInsideVisibleFrame() {
    let origin = PanelOrigin(x: -500, y: -50)
    let clamped = LauncherPosition.clampedOrigin(origin, panelSize: panel, visible: visible)
    XCTAssertEqual(clamped.x, 0, accuracy: 0.001)
    XCTAssertEqual(clamped.y, 0, accuracy: 0.001)
  }

  func testStoredOriginUsesSavedYAndCenterFlag() {
    let stored = LauncherStoredPosition(originY: 512, isHorizontallyCentered: true, originX: 0)
    let origin = LauncherPosition.origin(panelSize: panel, visible: visible, stored: stored)
    XCTAssertEqual(origin.y, 512, accuracy: 0.001)
    XCTAssertEqual(origin.x, visible.midX - panel.width / 2, accuracy: 0.001)
  }

  func testStoredOriginUsesSavedXWhenNotCentered() {
    let stored = LauncherStoredPosition(originY: 300, isHorizontallyCentered: false, originX: 120)
    let origin = LauncherPosition.origin(panelSize: panel, visible: visible, stored: stored)
    XCTAssertEqual(origin.x, 120, accuracy: 0.001)
    XCTAssertEqual(origin.y, 300, accuracy: 0.001)
  }
}
