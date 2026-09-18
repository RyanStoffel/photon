import Foundation

/// Keyboard list movement that does not wrap. Raycast-style: stop at the first and last rows
/// so Down on the last *visible* row can scroll instead of jumping to the top.
public enum SelectionNavigation: Sendable {
  /// Next index after moving `delta` steps. Empty lists stay at `0`.
  public static func moving(from index: Int, by delta: Int, count: Int) -> Int {
    guard count > 0 else {
      return 0
    }
    return min(max(index + delta, 0), count - 1)
  }

  /// Fully visible rows that fit in `listHeight` given row metrics.
  public static func visibleRowCount(listHeight: Double, rowHeight: Double, inset: Double) -> Int {
    max(1, Int((listHeight - 2 * inset) / rowHeight))
  }
}
