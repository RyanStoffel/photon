import Foundation

/// User-facing notes options. The app stores these in `SettingsStore` and pushes them here.
public struct NotesPreferences: Equatable, Sendable {
  public static let fontSizeRange: ClosedRange<Double> = 10 ... 28
  public static let defaultFontSize: Double = 14
  public static let fontSizeStep: Double = 1

  public var fontSize: Double {
    didSet {
      fontSize = Self.clampedFontSize(fontSize)
    }
  }

  public var floatsAboveOtherWindows: Bool

  public init(fontSize: Double = NotesPreferences.defaultFontSize, floatsAboveOtherWindows: Bool = true) {
    self.fontSize = Self.clampedFontSize(fontSize)
    self.floatsAboveOtherWindows = floatsAboveOtherWindows
  }

  public static func clampedFontSize(_ size: Double) -> Double {
    let rounded = size.rounded()
    return min(max(rounded, fontSizeRange.lowerBound), fontSizeRange.upperBound)
  }

  /// A copy with the font size moved by `steps` increments (negative to shrink), clamped to the range.
  public func adjustingFontSize(by steps: Int) -> NotesPreferences {
    var copy = self
    copy.fontSize = fontSize + Double(steps) * Self.fontSizeStep
    return copy
  }
}
