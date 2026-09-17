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
    XCTAssertEqual(guides.left, visible.midX - panel.width / 2, accuracy: 0.001)
    XCTAssertEqual(guides.right, visible.midX + panel.width / 2, accuracy: 0.001)
    XCTAssertGreaterThan(guides.right - guides.left, 600)
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

  func testOriginByMouseDeltaMatchesScreenSpace() {
    let start = PanelOrigin(x: 100, y: 400)
    let moved = LauncherPosition.originByMouseDelta(
      initialOrigin: start,
      startMouse: PanelOrigin(x: 50, y: 80),
      currentMouse: PanelOrigin(x: 90, y: 60)
    )
    XCTAssertEqual(moved.x, 140, accuracy: 0.001)
    XCTAssertEqual(moved.y, 380, accuracy: 0.001)
  }

  func testLiveDragSnapsXInsideGuideCorridor() {
    let start = PanelOrigin(x: visible.midX - panel.width / 2, y: 400)
    let mouse = PanelOrigin(x: visible.midX, y: 500)
    let origin = LauncherPosition.liveDragOrigin(
      initialOrigin: start,
      startMouse: mouse,
      currentMouse: PanelOrigin(x: mouse.x + 20, y: mouse.y - 80),
      panelWidth: panel.width,
      visible: visible
    )
    XCTAssertEqual(origin.x, start.x, accuracy: 0.001)
    XCTAssertEqual(origin.y, 320, accuracy: 0.001)
  }

  func testLiveDragKeepsOffsetWhenPulledOutsideGuides() {
    let start = PanelOrigin(x: visible.midX - panel.width / 2, y: 400)
    let mouse = PanelOrigin(x: visible.midX, y: 500)
    let outside = panel.width / 2 + 40
    let origin = LauncherPosition.liveDragOrigin(
      initialOrigin: start,
      startMouse: mouse,
      currentMouse: PanelOrigin(x: mouse.x + outside, y: mouse.y - 10),
      panelWidth: panel.width,
      visible: visible
    )
    XCTAssertEqual(origin.x, start.x + outside, accuracy: 0.001)
    XCTAssertEqual(origin.y, 390, accuracy: 0.001)
  }

  func testStoredPositionSnapsInsideCenterCorridorOnRelease() {
    let midInside = visible.midX
    let stored = LauncherPosition.storedPosition(
      origin: PanelOrigin(x: midInside - panel.width / 2, y: 400),
      panelWidth: panel.width,
      visible: visible
    )
    XCTAssertTrue(stored.isHorizontallyCentered)
  }

  func testResolveHorizontalSnapUsesGuideSpanNotCollapsedBand() {
    let offsetMidX = visible.midX + 80
    let result = LauncherPosition.resolveHorizontalSnap(
      panelMidX: offsetMidX,
      panelWidth: panel.width,
      visible: visible
    )
    XCTAssertTrue(result.isHorizontallyCentered)
  }

  func testSnapCorridorIsGuideSpanNotWholeScreenOnUltrawide() {
    let ultrawide = ScreenVisibleFrame(minX: 0, minY: 0, width: 3440, height: 1440)
    let panelWidth = 760.0
    let corridor = LauncherPosition.snapCorridor(visible: ultrawide, panelWidth: panelWidth)
    XCTAssertEqual(corridor.right - corridor.left, panelWidth, accuracy: 0.001)
    XCTAssertLessThan(corridor.right - corridor.left, ultrawide.width / 2)

    let inside = LauncherPosition.resolveHorizontalSnap(
      panelMidX: corridor.right - 1,
      panelWidth: panelWidth,
      visible: ultrawide
    )
    XCTAssertTrue(inside.isHorizontallyCentered)
    XCTAssertEqual(inside.originX, ultrawide.midX - panelWidth / 2, accuracy: 0.001)

    let outside = LauncherPosition.resolveHorizontalSnap(
      panelMidX: corridor.right + 1,
      panelWidth: panelWidth,
      visible: ultrawide
    )
    XCTAssertFalse(outside.isHorizontallyCentered)
    XCTAssertEqual(outside.originX, corridor.right + 1 - panelWidth / 2, accuracy: 0.001)
  }

  func testOriginByMouseDeltaIsStableWhenMouseHolds() {
    let start = PanelOrigin(x: 200, y: 300)
    let mouse = PanelOrigin(x: 10, y: 20)
    let held = LauncherPosition.originByMouseDelta(
      initialOrigin: start,
      startMouse: mouse,
      currentMouse: mouse
    )
    XCTAssertEqual(held.x, start.x, accuracy: 0.001)
    XCTAssertEqual(held.y, start.y, accuracy: 0.001)
  }

  func testStoredOriginUsesSavedXWhenNotCentered() {
    let stored = LauncherStoredPosition(originY: 300, isHorizontallyCentered: false, originX: 120)
    let origin = LauncherPosition.origin(panelSize: panel, visible: visible, stored: stored)
    XCTAssertEqual(origin.x, 120, accuracy: 0.001)
    XCTAssertEqual(origin.y, 300, accuracy: 0.001)
  }
}
