import Foundation

/// Fixed metrics of the notes window. Width is constant (slightly narrower than the Regular
/// launcher bar); height can grow with the window.
public enum NotesLayout: Sendable {
  /// Horizontal size of the notes panel. Regular launcher width is 760 pt.
  public static let panelWidth: Double = 680
  public static let defaultHeight: Double = 620
  public static let minimumHeight: Double = 360
  public static let footerHeight: Double = 36
  public static let overlayCardWidth: Double = 420
  public static let cornerRadius: Double = 12
  public static let editorHorizontalInset: Double = 22
  public static let editorVerticalInset: Double = 12

  public static var defaultSize: CGSize {
    CGSize(width: panelWidth, height: defaultHeight)
  }

  public static var minimumSize: CGSize {
    CGSize(width: panelWidth, height: minimumHeight)
  }

  /// Width never changes; height is clamped to at least `minimumHeight`.
  public static func constrainedSize(from proposed: CGSize) -> CGSize {
    CGSize(width: panelWidth, height: max(proposed.height, minimumHeight))
  }

  public static func characterCountLabel(_ count: Int, capitalized: Bool) -> String {
    let noun = count == 1 ? "character" : "characters"
    if capitalized {
      return "\(count) \(noun.prefix(1).uppercased())\(noun.dropFirst())"
    }
    return "\(count) \(noun)"
  }
}
