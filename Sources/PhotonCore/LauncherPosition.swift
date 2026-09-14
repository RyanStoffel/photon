import Foundation

/// Visible area of a display in AppKit coordinates (origin bottom-left).
public struct ScreenVisibleFrame: Equatable, Sendable {
  public var minX: Double
  public var minY: Double
  public var width: Double
  public var height: Double

  public init(minX: Double, minY: Double, width: Double, height: Double) {
    self.minX = minX
    self.minY = minY
    self.width = width
    self.height = height
  }

  public var midX: Double {
    minX + width / 2
  }

  public var maxY: Double {
    minY + height
  }
}

public struct PanelSize: Equatable, Sendable {
  public var width: Double
  public var height: Double

  public init(width: Double, height: Double) {
    self.width = width
    self.height = height
  }
}

public struct PanelOrigin: Equatable, Sendable {
  public var x: Double
  public var y: Double

  public init(x: Double, y: Double) {
    self.x = x
    self.y = y
  }
}

/// User-customized launcher placement. `originX` is ignored when centered horizontally.
public struct LauncherStoredPosition: Equatable, Codable, Sendable {
  public var originY: Double
  public var isHorizontallyCentered: Bool
  public var originX: Double

  public init(originY: Double, isHorizontallyCentered: Bool, originX: Double) {
    self.originY = originY
    self.isHorizontallyCentered = isHorizontallyCentered
    self.originX = originX
  }
}

/// Default placement and snap geometry for the launcher panel.
public enum LauncherPosition {
  /// Spotlight-like default: centred horizontally, top edge ~74% up the visible frame.
  public static func defaultOrigin(panelSize: PanelSize, visible: ScreenVisibleFrame) -> PanelOrigin {
    let top = min(visible.minY + visible.height * 0.74, visible.maxY - 8)
    return PanelOrigin(
      x: visible.midX - panelSize.width / 2,
      y: top - panelSize.height
    )
  }

  public static func origin(
    panelSize: PanelSize,
    visible: ScreenVisibleFrame,
    stored: LauncherStoredPosition?
  ) -> PanelOrigin {
    guard let stored else {
      return defaultOrigin(panelSize: panelSize, visible: visible)
    }
    let x = stored.isHorizontallyCentered
      ? visible.midX - panelSize.width / 2
      : stored.originX
    return clampedOrigin(PanelOrigin(x: x, y: stored.originY), panelSize: panelSize, visible: visible)
  }

  public static func clampedOrigin(
    _ origin: PanelOrigin,
    panelSize: PanelSize,
    visible: ScreenVisibleFrame
  ) -> PanelOrigin {
    let minX = visible.minX
    let maxX = visible.minX + visible.width - panelSize.width
    let minY = visible.minY
    let maxY = visible.maxY - panelSize.height
    return PanelOrigin(
      x: min(max(origin.x, minX), maxX),
      y: min(max(origin.y, minY), maxY)
    )
  }

  /// Horizontal positions of the two snap guides in screen coordinates.
  /// When the panel is centred, guides sit on the panel's left and right edges.
  public static func snapGuideXPositions(
    visible: ScreenVisibleFrame,
    panelWidth: Double
  ) -> (left: Double, right: Double) {
    (
      visible.midX - panelWidth / 2,
      visible.midX + panelWidth / 2
    )
  }

  /// Resolves horizontal placement after a drag ends.
  public static func resolveHorizontalSnap(
    panelMidX: Double,
    panelWidth: Double,
    visible: ScreenVisibleFrame
  ) -> (originX: Double, isHorizontallyCentered: Bool) {
    let guides = snapGuideXPositions(visible: visible, panelWidth: panelWidth)
    if panelMidX >= guides.left, panelMidX <= guides.right {
      return (visible.midX - panelWidth / 2, true)
    }
    return (panelMidX - panelWidth / 2, false)
  }

  /// Live drag origin from screen-space mouse movement. AppKit and `NSEvent.mouseLocation`
  /// share a bottom-left origin, so the deltas apply directly (no Y flip).
  public static func originByMouseDelta(
    initialOrigin: PanelOrigin,
    startMouse: PanelOrigin,
    currentMouse: PanelOrigin
  ) -> PanelOrigin {
    PanelOrigin(
      x: initialOrigin.x + (currentMouse.x - startMouse.x),
      y: initialOrigin.y + (currentMouse.y - startMouse.y)
    )
  }

  public static func storedPosition(
    origin: PanelOrigin,
    panelWidth: Double,
    visible: ScreenVisibleFrame
  ) -> LauncherStoredPosition {
    let midX = origin.x + panelWidth / 2
    let horizontal = resolveHorizontalSnap(panelMidX: midX, panelWidth: panelWidth, visible: visible)
    return LauncherStoredPosition(
      originY: origin.y,
      isHorizontallyCentered: horizontal.isHorizontallyCentered,
      originX: horizontal.originX
    )
  }
}
