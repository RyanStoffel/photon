import Foundation

/// One entry of the HID system's `UserKeyMapping` property, the same thing `hidutil property --set` writes.
public struct HIDKeyMappingPair: Hashable, Sendable {
  public var source: UInt64
  public var destination: UInt64

  public init(source: UInt64, destination: UInt64) {
    self.source = source
    self.destination = destination
  }
}

/// Pure helpers for reading and writing `hidutil`'s `UserKeyMapping` format.
public enum HIDKeyMapping {
  public static let propertyKey = "UserKeyMapping"
  public static let sourceKey = "HIDKeyboardModifierMappingSrc"
  public static let destinationKey = "HIDKeyboardModifierMappingDst"

  /// Parses the output of `hidutil property --get UserKeyMapping`, which prints an `NSArray` description
  /// such as `( { HIDKeyboardModifierMappingDst = 30064771181; HIDKeyboardModifierMappingSrc = 30064771129; } )`.
  public static func parse(hidutilOutput text: String) -> [HIDKeyMappingPair] {
    var pairs: [HIDKeyMappingPair] = []
    for block in text.components(separatedBy: "}") {
      guard let source = integer(after: sourceKey, in: block),
            let destination = integer(after: destinationKey, in: block)
      else {
        continue
      }
      pairs.append(HIDKeyMappingPair(source: source, destination: destination))
    }
    return pairs
  }

  /// Argument for `hidutil property --set`.
  public static func propertyArgument(for pairs: [HIDKeyMappingPair]) -> String {
    let entries = pairs.map {
      "{\"\(sourceKey)\":\($0.source),\"\(destinationKey)\":\($0.destination)}"
    }
    return "{\"\(propertyKey)\":[\(entries.joined(separator: ","))]}"
  }

  /// Replaces any existing mapping of the same source key.
  public static func merging(_ existing: [HIDKeyMappingPair], with pair: HIDKeyMappingPair) -> [HIDKeyMappingPair] {
    existing.filter { $0.source != pair.source } + [pair]
  }

  /// Drops every mapping that sends one of `sources` to `destination`.
  public static func removing(
    sources: Set<UInt64>,
    destination: UInt64,
    from existing: [HIDKeyMappingPair]
  ) -> [HIDKeyMappingPair] {
    existing.filter { !(sources.contains($0.source) && $0.destination == destination) }
  }

  private static func integer(after key: String, in block: String) -> UInt64? {
    guard let keyRange = block.range(of: key) else {
      return nil
    }
    var scanner = block[keyRange.upperBound...].drop { $0 == " " || $0 == "=" || $0 == "\"" || $0 == ":" }
    if scanner.hasPrefix("0x") || scanner.hasPrefix("0X") {
      scanner = scanner.dropFirst(2)
      let digits = scanner.prefix { $0.isHexDigit }
      return UInt64(digits, radix: 16)
    }
    let digits = scanner.prefix { $0.isNumber }
    return UInt64(digits)
  }
}
