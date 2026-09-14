import Foundation
import PhotonKeybinds
import XCTest

final class WindowLayoutTests: XCTestCase {
  /// Visible frames (bottom-left origin) for a few realistic setups.
  private let screens: [String: CGRect] = [
    "macbook-dock-bottom": CGRect(x: 0, y: 70, width: 1440, height: 805),
    "4k-right-of-primary": CGRect(x: 1440, y: 0, width: 3840, height: 2135),
    "odd-size-dock-left": CGRect(x: 60, y: 0, width: 1219, height: 776),
    "display-above-primary": CGRect(x: -200, y: 900, width: 2560, height: 1415)
  ]

  private let window = CGRect(x: 100, y: 200, width: 800, height: 500)

  private var layoutActions: [WindowAction] {
    WindowAction.allCases.filter(\.isLayout)
  }

  func testEveryLayoutFitsInsideTheVisibleFrameWithIntegerCoordinates() {
    for (name, visible) in screens {
      for action in layoutActions {
        guard let frame = WindowLayout.frame(for: action, window: window, in: visible) else {
          XCTFail("\(action) produced no frame on \(name)")
          continue
        }
        XCTAssertTrue(visible.contains(frame), "\(action) leaves \(name): \(frame) vs \(visible)")
        XCTAssertEqual(frame.minX, frame.minX.rounded(), "\(action) x on \(name)")
        XCTAssertEqual(frame.minY, frame.minY.rounded(), "\(action) y on \(name)")
        XCTAssertEqual(frame.width, frame.width.rounded(), "\(action) width on \(name)")
        XCTAssertEqual(frame.height, frame.height.rounded(), "\(action) height on \(name)")
        XCTAssertGreaterThan(frame.width, 0)
        XCTAssertGreaterThan(frame.height, 0)
      }
    }
  }

  func testNonLayoutActionsHaveNoFrame() throws {
    for action in [WindowAction.nextDisplay, .previousDisplay, .restore] {
      XCTAssertNil(try WindowLayout.frame(for: action, window: window, in: XCTUnwrap(screens["macbook-dock-bottom"])))
    }
  }

  func testHalvesTileTheDisplay() {
    for (name, visible) in screens {
      let left = frame(.leftHalf, visible)
      let right = frame(.rightHalf, visible)
      assertTilesHorizontally([left, right], visible, name)

      let top = frame(.topHalf, visible)
      let bottom = frame(.bottomHalf, visible)
      assertTilesVertically([top, bottom], visible, name)
      XCTAssertGreaterThan(top.minY, bottom.minY, "top half must sit above bottom half on \(name)")
    }
  }

  func testQuartersTileTheDisplay() {
    for (name, visible) in screens {
      let topLeft = frame(.topLeftQuarter, visible)
      let topRight = frame(.topRightQuarter, visible)
      let bottomLeft = frame(.bottomLeftQuarter, visible)
      let bottomRight = frame(.bottomRightQuarter, visible)

      XCTAssertEqual(topLeft.maxY, visible.maxY, name)
      XCTAssertEqual(topRight.maxY, visible.maxY, name)
      XCTAssertEqual(bottomLeft.minY, visible.minY, name)
      XCTAssertEqual(bottomRight.minY, visible.minY, name)
      XCTAssertEqual(topLeft.maxX, topRight.minX, name)
      XCTAssertEqual(bottomLeft.maxX, bottomRight.minX, name)
      XCTAssertEqual(topLeft.minY, bottomLeft.maxY, name)
      XCTAssertEqual(topRight.minY, bottomRight.maxY, name)
      XCTAssertEqual(topLeft.union(topRight).union(bottomLeft).union(bottomRight), visible, name)
      XCTAssertEqual(topLeft, frame(.leftHalf, visible).intersection(frame(.topHalf, visible)), name)
    }
  }

  func testThirdsTileTheDisplay() {
    for (name, visible) in screens {
      let left = frame(.leftThird, visible)
      let center = frame(.centerThird, visible)
      let right = frame(.rightThird, visible)
      assertTilesHorizontally([left, center, right], visible, name)
      XCTAssertLessThanOrEqual(abs(left.width - right.width), 1, name)
      XCTAssertLessThanOrEqual(abs(left.width - center.width), 1, name)
    }
  }

  func testTwoThirdsSpanTwoColumns() {
    for (name, visible) in screens {
      let leftTwo = frame(.leftTwoThirds, visible)
      let rightTwo = frame(.rightTwoThirds, visible)
      XCTAssertEqual(leftTwo, frame(.leftThird, visible).union(frame(.centerThird, visible)), name)
      XCTAssertEqual(rightTwo, frame(.centerThird, visible).union(frame(.rightThird, visible)), name)
    }
  }

  func testMaximizeFillsTheVisibleFrame() {
    for (name, visible) in screens {
      XCTAssertEqual(frame(.maximize, visible), visible, name)
    }
  }

  func testAlmostMaximizeIsNinetyPercentCentered() {
    for (name, visible) in screens {
      let frame = frame(.almostMaximize, visible)
      XCTAssertEqual(frame.width, (visible.width * 0.9).rounded(), name)
      XCTAssertEqual(frame.height, (visible.height * 0.9).rounded(), name)
      XCTAssertLessThanOrEqual(abs(frame.midX - visible.midX), 1, name)
      XCTAssertLessThanOrEqual(abs(frame.midY - visible.midY), 1, name)
    }
  }

  func testCenterKeepsSizeAndCentersTheWindow() {
    for (name, visible) in screens {
      let frame = frame(.center, visible)
      XCTAssertEqual(frame.size, window.size, name)
      XCTAssertLessThanOrEqual(abs(frame.midX - visible.midX), 1, name)
      XCTAssertLessThanOrEqual(abs(frame.midY - visible.midY), 1, name)
    }
  }

  func testCenterShrinksWindowsLargerThanTheDisplay() throws {
    let visible = try XCTUnwrap(screens["macbook-dock-bottom"])
    let huge = CGRect(x: 0, y: 0, width: 5000, height: 4000)
    let frame = try XCTUnwrap(WindowLayout.frame(for: .center, window: huge, in: visible))
    XCTAssertEqual(frame, visible)
  }

  func testTranslateKeepsRelativePositionAndSize() throws {
    let source = try XCTUnwrap(screens["macbook-dock-bottom"])
    let target = try XCTUnwrap(screens["4k-right-of-primary"])
    let left = frame(.leftHalf, source)
    let moved = WindowLayout.translate(left, from: source, to: target)
    XCTAssertEqual(moved.minX, target.minX)
    XCTAssertEqual(moved.width, (target.width / 2).rounded())
    XCTAssertEqual(moved.height, target.height)
    XCTAssertTrue(target.contains(moved))

    let maximized = WindowLayout.translate(source, from: source, to: target)
    XCTAssertEqual(maximized, target)
  }

  func testTranslateClampsWhenTheTargetIsSmaller() throws {
    let source = try XCTUnwrap(screens["4k-right-of-primary"])
    let target = try XCTUnwrap(screens["odd-size-dock-left"])
    let big = CGRect(x: source.minX + 100, y: source.minY + 100, width: 3600, height: 2000)
    let moved = WindowLayout.translate(big, from: source, to: target)
    XCTAssertTrue(target.contains(moved), "\(moved) is not inside \(target)")
  }

  func testFitShrinksAndShiftsIntoBounds() {
    let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
    XCTAssertEqual(
      WindowLayout.fit(CGRect(x: 900, y: 700, width: 300, height: 300), in: bounds),
      CGRect(x: 700, y: 500, width: 300, height: 300)
    )
    XCTAssertEqual(
      WindowLayout.fit(CGRect(x: -50, y: -50, width: 2000, height: 100), in: bounds),
      CGRect(x: 0, y: 0, width: 1000, height: 100)
    )
  }

  func testScreenIndexPrefersTheLargestOverlap() {
    let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let secondary = CGRect(x: 1440, y: 0, width: 2560, height: 1440)
    let mostlyOnSecondary = CGRect(x: 1200, y: 100, width: 800, height: 500)
    XCTAssertEqual(WindowLayout.screenIndex(for: mostlyOnSecondary, screens: [primary, secondary]), 1)
    let mostlyOnPrimary = CGRect(x: 800, y: 100, width: 800, height: 500)
    XCTAssertEqual(WindowLayout.screenIndex(for: mostlyOnPrimary, screens: [primary, secondary]), 0)
  }

  func testScreenIndexFallsBackToCenterThenNil() {
    let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let zeroSize = CGRect(x: 1000, y: 500, width: 0, height: 0)
    XCTAssertEqual(WindowLayout.screenIndex(for: zeroSize, screens: [primary]), 0)
    let offscreen = CGRect(x: 5000, y: 5000, width: 100, height: 100)
    XCTAssertNil(WindowLayout.screenIndex(for: offscreen, screens: [primary]))
  }

  func testDisplayOrderGoesLeftToRightThenTopToBottom() {
    let screens = [
      CGRect(x: 1440, y: 0, width: 2560, height: 1440),
      CGRect(x: 0, y: 0, width: 1440, height: 900),
      CGRect(x: 0, y: 900, width: 1440, height: 900)
    ]
    XCTAssertEqual(WindowLayout.displayOrder(screens), [2, 1, 0])
    XCTAssertEqual(WindowLayout.displayIndex(from: 0, step: 1, screens: screens), 2)
    XCTAssertEqual(WindowLayout.displayIndex(from: 2, step: -1, screens: screens), 0)
    XCTAssertEqual(WindowLayout.displayIndex(from: 1, step: 1, screens: screens), 0)
    XCTAssertEqual(WindowLayout.displayIndex(from: 0, step: 1, screens: [screens[0]]), 0)
  }

  func testFlippedConvertsBetweenCocoaAndAccessibilityCoordinates() {
    let primaryHeight: CGFloat = 900
    let cocoa = CGRect(x: 100, y: 100, width: 800, height: 500)
    let accessibility = WindowLayout.flipped(cocoa, primaryHeight: primaryHeight)
    XCTAssertEqual(accessibility, CGRect(x: 100, y: 300, width: 800, height: 500))

    let above = CGRect(x: 0, y: 900, width: 1440, height: 900)
    let flippedAbove = WindowLayout.flipped(above, primaryHeight: primaryHeight)
    XCTAssertEqual(flippedAbove, CGRect(x: 0, y: -900, width: 1440, height: 900))

    for (_, visible) in screens {
      let once = WindowLayout.flipped(visible, primaryHeight: primaryHeight)
      XCTAssertEqual(WindowLayout.flipped(once, primaryHeight: primaryHeight), visible)
    }
  }

  func testDefaultShortcutsExistForTheDocumentedCommands() {
    XCTAssertEqual(WindowAction.leftHalf.defaultShortcut, KeyShortcut.parse("hyper+left"))
    XCTAssertEqual(WindowAction.rightHalf.defaultShortcut, KeyShortcut.parse("hyper+right"))
    XCTAssertEqual(WindowAction.topHalf.defaultShortcut, KeyShortcut.parse("hyper+up"))
    XCTAssertEqual(WindowAction.bottomHalf.defaultShortcut, KeyShortcut.parse("hyper+down"))
    XCTAssertEqual(WindowAction.maximize.defaultShortcut, KeyShortcut.parse("hyper+return"))
    XCTAssertEqual(WindowAction.center.defaultShortcut, KeyShortcut.parse("hyper+c"))
    XCTAssertEqual(WindowAction.nextDisplay.defaultShortcut, KeyShortcut.parse("hyper+]"))
    XCTAssertEqual(WindowAction.previousDisplay.defaultShortcut, KeyShortcut.parse("hyper+["))
    XCTAssertNil(WindowAction.restore.defaultShortcut)
    XCTAssertEqual(WindowAction.allCases.count, 19)
  }

  // MARK: - Helpers

  private func frame(_ action: WindowAction, _ visible: CGRect) -> CGRect {
    WindowLayout.frame(for: action, window: window, in: visible) ?? .null
  }

  private func assertTilesHorizontally(_ frames: [CGRect], _ visible: CGRect, _ name: String) {
    for frame in frames {
      XCTAssertEqual(frame.minY, visible.minY, name)
      XCTAssertEqual(frame.height, visible.height, name)
    }
    XCTAssertEqual(frames.first?.minX, visible.minX, name)
    XCTAssertEqual(frames.last?.maxX, visible.maxX, name)
    for (left, right) in zip(frames, frames.dropFirst()) {
      XCTAssertEqual(left.maxX, right.minX, "gap or overlap between columns on \(name)")
    }
  }

  private func assertTilesVertically(_ frames: [CGRect], _ visible: CGRect, _ name: String) {
    for frame in frames {
      XCTAssertEqual(frame.minX, visible.minX, name)
      XCTAssertEqual(frame.width, visible.width, name)
    }
    XCTAssertEqual(frames.first?.maxY, visible.maxY, name)
    XCTAssertEqual(frames.last?.minY, visible.minY, name)
    for (upper, lower) in zip(frames, frames.dropFirst()) {
      XCTAssertEqual(upper.minY, lower.maxY, "gap or overlap between rows on \(name)")
    }
  }
}
