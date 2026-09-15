import Foundation

/// Every window command Photon offers. Raw values are stable identifiers used in settings and command ids.
public enum WindowAction: String, CaseIterable, Codable, Sendable, Identifiable {
  case leftHalf
  case rightHalf
  case topHalf
  case bottomHalf
  case topLeftQuarter
  case topRightQuarter
  case bottomLeftQuarter
  case bottomRightQuarter
  case leftThird
  case centerThird
  case rightThird
  case leftTwoThirds
  case rightTwoThirds
  case maximize
  case almostMaximize
  case center
  case nextDisplay
  case previousDisplay
  case restore

  public var id: String {
    rawValue
  }

  public var title: String {
    Self.metadata[self]?.title ?? rawValue
  }

  public var keywords: [String] {
    Self.metadata[self]?.keywords ?? []
  }

  public var defaultShortcut: KeyShortcut? {
    guard let key = Self.metadata[self]?.defaultKey else {
      return nil
    }
    return KeyShortcut(.hyper, key)
  }

  /// True when the action resizes within the current display (as opposed to moving displays or restoring).
  public var isLayout: Bool {
    switch self {
    case .nextDisplay, .previousDisplay, .restore:
      false
    default:
      true
    }
  }

  private struct Metadata {
    let title: String
    let keywords: [String]
    let defaultKey: String?
  }

  private static let metadata: [WindowAction: Metadata] = [
    .leftHalf: Metadata(title: "Left Half", keywords: ["half", "snap"], defaultKey: "left"),
    .rightHalf: Metadata(title: "Right Half", keywords: ["half", "snap"], defaultKey: "right"),
    .topHalf: Metadata(title: "Top Half", keywords: ["half", "snap"], defaultKey: "up"),
    .bottomHalf: Metadata(title: "Bottom Half", keywords: ["half", "snap"], defaultKey: "down"),
    .topLeftQuarter: Metadata(title: "Top Left Quarter", keywords: ["quarter", "corner"], defaultKey: nil),
    .topRightQuarter: Metadata(title: "Top Right Quarter", keywords: ["quarter", "corner"], defaultKey: nil),
    .bottomLeftQuarter: Metadata(title: "Bottom Left Quarter", keywords: ["quarter", "corner"], defaultKey: nil),
    .bottomRightQuarter: Metadata(title: "Bottom Right Quarter", keywords: ["quarter", "corner"], defaultKey: nil),
    .leftThird: Metadata(title: "Left Third", keywords: ["third"], defaultKey: nil),
    .centerThird: Metadata(title: "Center Third", keywords: ["third", "middle"], defaultKey: nil),
    .rightThird: Metadata(title: "Right Third", keywords: ["third"], defaultKey: nil),
    .leftTwoThirds: Metadata(title: "Left Two Thirds", keywords: ["thirds", "two-thirds"], defaultKey: nil),
    .rightTwoThirds: Metadata(title: "Right Two Thirds", keywords: ["thirds", "two-thirds"], defaultKey: nil),
    .maximize: Metadata(title: "Maximize", keywords: ["fullscreen", "fill", "zoom"], defaultKey: "return"),
    .almostMaximize: Metadata(title: "Almost Maximize", keywords: ["large", "fill"], defaultKey: nil),
    .center: Metadata(title: "Center", keywords: ["middle"], defaultKey: "c"),
    .nextDisplay: Metadata(title: "Next Display", keywords: ["screen", "monitor", "move"], defaultKey: "]"),
    .previousDisplay: Metadata(title: "Previous Display", keywords: ["screen", "monitor", "move"], defaultKey: "["),
    .restore: Metadata(title: "Restore", keywords: ["undo", "previous", "size"], defaultKey: nil)
  ]
}

/// Frame math for window commands. Pure functions; no AppKit.
///
/// All rectangles share one coordinate space with the origin at the bottom left (Cocoa `NSScreen`
/// convention), so "top" means larger `y`. `flipped(_:primaryHeight:)` converts to and from the
/// Accessibility API's top-left origin.
public enum WindowLayout {
  public static let almostMaximizeFraction: CGFloat = 0.9

  /// Grid cell: `column`/`row` are zero-based, row 0 is the top row.
  private struct Cell {
    let columns: Int
    let rows: Int
    let column: Int
    let row: Int
    let columnSpan: Int
    let rowSpan: Int
  }

  private static let cells: [WindowAction: Cell] = [
    .leftHalf: Cell(columns: 2, rows: 1, column: 0, row: 0, columnSpan: 1, rowSpan: 1),
    .rightHalf: Cell(columns: 2, rows: 1, column: 1, row: 0, columnSpan: 1, rowSpan: 1),
    .topHalf: Cell(columns: 1, rows: 2, column: 0, row: 0, columnSpan: 1, rowSpan: 1),
    .bottomHalf: Cell(columns: 1, rows: 2, column: 0, row: 1, columnSpan: 1, rowSpan: 1),
    .topLeftQuarter: Cell(columns: 2, rows: 2, column: 0, row: 0, columnSpan: 1, rowSpan: 1),
    .topRightQuarter: Cell(columns: 2, rows: 2, column: 1, row: 0, columnSpan: 1, rowSpan: 1),
    .bottomLeftQuarter: Cell(columns: 2, rows: 2, column: 0, row: 1, columnSpan: 1, rowSpan: 1),
    .bottomRightQuarter: Cell(columns: 2, rows: 2, column: 1, row: 1, columnSpan: 1, rowSpan: 1),
    .leftThird: Cell(columns: 3, rows: 1, column: 0, row: 0, columnSpan: 1, rowSpan: 1),
    .centerThird: Cell(columns: 3, rows: 1, column: 1, row: 0, columnSpan: 1, rowSpan: 1),
    .rightThird: Cell(columns: 3, rows: 1, column: 2, row: 0, columnSpan: 1, rowSpan: 1),
    .leftTwoThirds: Cell(columns: 3, rows: 1, column: 0, row: 0, columnSpan: 2, rowSpan: 1),
    .rightTwoThirds: Cell(columns: 3, rows: 1, column: 1, row: 0, columnSpan: 2, rowSpan: 1),
    .maximize: Cell(columns: 1, rows: 1, column: 0, row: 0, columnSpan: 1, rowSpan: 1)
  ]

  /// Target frame for a layout action inside `visible` (the display's visible frame).
  /// Returns `nil` for actions that are not in-display layouts (`nextDisplay`, `previousDisplay`, `restore`).
  public static func frame(for action: WindowAction, window: CGRect, in visible: CGRect) -> CGRect? {
    if let cell = cells[action] {
      return gridFrame(cell, in: visible)
    }
    switch action {
    case .almostMaximize:
      let size = CGSize(
        width: (visible.width * almostMaximizeFraction).rounded(),
        height: (visible.height * almostMaximizeFraction).rounded()
      )
      return centered(size: size, in: visible)
    case .center:
      let size = CGSize(
        width: min(window.width, visible.width),
        height: min(window.height, visible.height)
      )
      return centered(size: size, in: visible)
    default:
      return nil
    }
  }

  /// Maps `window` from `source` to `target` keeping its relative position and size, then fits it.
  public static func translate(_ window: CGRect, from source: CGRect, to target: CGRect) -> CGRect {
    guard source.width > 0, source.height > 0 else {
      return fit(window, in: target)
    }
    let relativeX = (window.minX - source.minX) / source.width
    let relativeY = (window.minY - source.minY) / source.height
    let scaled = CGRect(
      x: (target.minX + relativeX * target.width).rounded(),
      y: (target.minY + relativeY * target.height).rounded(),
      width: (window.width / source.width * target.width).rounded(),
      height: (window.height / source.height * target.height).rounded()
    )
    return fit(scaled, in: target)
  }

  /// Shrinks `frame` to `bounds` if needed, then shifts it so it lies inside `bounds`.
  public static func fit(_ frame: CGRect, in bounds: CGRect) -> CGRect {
    var result = frame
    result.size.width = min(result.width, bounds.width)
    result.size.height = min(result.height, bounds.height)
    if result.maxX > bounds.maxX {
      result.origin.x = bounds.maxX - result.width
    }
    if result.minX < bounds.minX {
      result.origin.x = bounds.minX
    }
    if result.maxY > bounds.maxY {
      result.origin.y = bounds.maxY - result.height
    }
    if result.minY < bounds.minY {
      result.origin.y = bounds.minY
    }
    return result
  }

  /// Index of the screen showing most of `window`; falls back to the one containing its center.
  public static func screenIndex(for window: CGRect, screens: [CGRect]) -> Int? {
    var bestIndex: Int?
    var bestArea: CGFloat = 0
    for (index, screen) in screens.enumerated() {
      let overlap = screen.intersection(window)
      guard !overlap.isNull, !overlap.isEmpty else {
        continue
      }
      let area = overlap.width * overlap.height
      if area > bestArea {
        bestArea = area
        bestIndex = index
      }
    }
    if let bestIndex {
      return bestIndex
    }
    let center = CGPoint(x: window.midX, y: window.midY)
    return screens.firstIndex { $0.contains(center) }
  }

  /// Display order for cycling: left to right, then top to bottom.
  public static func displayOrder(_ screens: [CGRect]) -> [Int] {
    screens.indices.sorted { lhs, rhs in
      if screens[lhs].minX != screens[rhs].minX {
        return screens[lhs].minX < screens[rhs].minX
      }
      return screens[lhs].maxY > screens[rhs].maxY
    }
  }

  /// Screen index `step` displays after `current` in `displayOrder`, wrapping around.
  public static func displayIndex(from current: Int, step: Int, screens: [CGRect]) -> Int {
    let order = displayOrder(screens)
    guard let position = order.firstIndex(of: current), !order.isEmpty else {
      return current
    }
    let count = order.count
    let next = ((position + step) % count + count) % count
    return order[next]
  }

  /// Converts between bottom-left (Cocoa) and top-left (Accessibility) origins. The function is its own inverse.
  public static func flipped(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
    CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
  }

  private static func gridFrame(_ cell: Cell, in visible: CGRect) -> CGRect {
    let left = edge(visible.minX, length: visible.width, fraction: cell.column, of: cell.columns)
    let right = edge(visible.minX, length: visible.width, fraction: cell.column + cell.columnSpan, of: cell.columns)
    let top = visible.maxY - edge(0, length: visible.height, fraction: cell.row, of: cell.rows)
    let bottom = visible.maxY - edge(0, length: visible.height, fraction: cell.row + cell.rowSpan, of: cell.rows)
    return CGRect(x: left, y: bottom, width: right - left, height: top - bottom)
  }

  private static func edge(
    _ origin: CGFloat,
    length: CGFloat,
    fraction numerator: Int,
    of denominator: Int
  ) -> CGFloat {
    (origin + length * CGFloat(numerator) / CGFloat(denominator)).rounded()
  }

  private static func centered(size: CGSize, in visible: CGRect) -> CGRect {
    CGRect(
      x: (visible.midX - size.width / 2).rounded(),
      y: (visible.midY - size.height / 2).rounded(),
      width: size.width,
      height: size.height
    )
  }
}
