import Foundation

enum UnitConversion {
  static func evaluate(_ input: String) -> CalculatorResult? {
    let lowered = input.lowercased()
    guard let separatorRange = lowered.range(of: #"\b(to|in)\b"#, options: .regularExpression) else {
      return nil
    }
    let left = String(input[input.startIndex ..< separatorRange.lowerBound]).trimmingCharacters(in: .whitespaces)
    let right = String(input[separatorRange.upperBound...]).trimmingCharacters(in: .whitespaces)
    guard let (amount, fromOptional) = parseAmountUnit(left),
          let from = fromOptional,
          let to = resolveUnit(right)
    else {
      return nil
    }
    guard let converted = convert(amount: amount, from: from, to: to) else {
      return nil
    }
    let valueText = format(converted, unit: to)
    return CalculatorResult(
      expression: compactExpression(input),
      value: stripUnit(valueText),
      operationLabel: "Convert",
      wordForm: NumberWords.spokenForm(for: converted)
    )
  }

  private static func compactExpression(_ input: String) -> String {
    input.split(whereSeparator: \.isWhitespace).joined(separator: " ")
  }

  private static func parseAmountUnit(_ text: String) -> (Double, UnitKind?)? {
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    let parts = trimmed.split(whereSeparator: \.isWhitespace)
    if parts.count >= 2 {
      let numberToken = parts.dropLast().joined(separator: " ")
      guard let amount = Double(numberToken) else {
        return nil
      }
      return (amount, resolveUnit(String(parts.last!)))
    }
    guard let regex = try? NSRegularExpression(pattern: #"^([+-]?(?:\d+(?:\.\d+)?|\.\d+))(.+)$"#),
          let found = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
          let numberRange = Range(found.range(at: 1), in: trimmed),
          let unitRange = Range(found.range(at: 2), in: trimmed),
          let amount = Double(trimmed[numberRange])
    else {
      return nil
    }
    return (amount, resolveUnit(String(trimmed[unitRange])))
  }

  private enum UnitKind: Equatable {
    case length(LengthUnit)
    case mass(MassUnit)
    case temperature(TemperatureUnit)
    case time(TimeUnit)
    case data(DataUnit)
  }

  private enum LengthUnit: String {
    case m, km, cm, mm, mi, mile, miles, ft, foot, feet, inch, inches, yd, yard, yards
  }

  private enum MassUnit: String {
    case g, gram, grams, kg, kilogram, kilograms, lb, lbs, pound, pounds, oz, ounce, ounces
  }

  private enum TemperatureUnit: String {
    case c, cel, celsius, f, fah, fahrenheit, k, kelvin
  }

  private enum TimeUnit: String {
    case s, sec, secs, second, seconds, min, mins, minute, minutes, h, hr, hrs, hour, hours
    case d, day, days, wk, week, weeks
  }

  private enum DataUnit: String {
    case b, bit, bits, byte, bytes, kb, mb, gb, tb, kib, mib, gib, tib
  }

  private static func resolveUnit(_ token: String) -> UnitKind? {
    let cleaned = token
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .trimmingCharacters(in: CharacterSet(charactersIn: "°"))
      .lowercased()
    if cleaned == "in" {
      return .length(.inch)
    }
    if let unit = LengthUnit(rawValue: cleaned) {
      return .length(unit)
    }
    if let unit = MassUnit(rawValue: cleaned) {
      return .mass(unit)
    }
    if let unit = TemperatureUnit(rawValue: cleaned) {
      return .temperature(unit)
    }
    if let unit = TimeUnit(rawValue: cleaned) {
      return .time(unit)
    }
    if let unit = DataUnit(rawValue: cleaned) {
      return .data(unit)
    }
    return nil
  }

  private static func convert(amount: Double, from: UnitKind, to: UnitKind) -> Double? {
    guard sameCategory(from, to) else {
      return nil
    }
    switch (from, to) {
    case let (.length(a), .length(b)):
      return lengthToMeters(amount, unit: a) / lengthToMeters(1, unit: b)
    case let (.mass(a), .mass(b)):
      return massToGrams(amount, unit: a) / massToGrams(1, unit: b)
    case let (.temperature(a), .temperature(b)):
      return convertTemperature(amount, from: a, to: b)
    case let (.time(a), .time(b)):
      return timeToSeconds(amount, unit: a) / timeToSeconds(1, unit: b)
    case let (.data(a), .data(b)):
      return dataToBytes(amount, unit: a) / dataToBytes(1, unit: b)
    default:
      return nil
    }
  }

  private static func sameCategory(_ lhs: UnitKind, _ rhs: UnitKind) -> Bool {
    switch (lhs, rhs) {
    case (.length, .length), (.mass, .mass), (.temperature, .temperature), (.time, .time), (.data, .data):
      true
    default:
      false
    }
  }

  private static func lengthToMeters(_ value: Double, unit: LengthUnit) -> Double {
    switch unit {
    case .m: value
    case .km: value * 1000
    case .cm: value / 100
    case .mm: value / 1000
    case .mi, .mile, .miles: value * 1609.344
    case .ft, .foot, .feet: value * 0.3048
    case .inch, .inches: value * 0.0254
    case .yd, .yard, .yards: value * 0.9144
    }
  }

  private static func massToGrams(_ value: Double, unit: MassUnit) -> Double {
    switch unit {
    case .g, .gram, .grams: value
    case .kg, .kilogram, .kilograms: value * 1000
    case .lb, .lbs, .pound, .pounds: value * 453.59237
    case .oz, .ounce, .ounces: value * 28.349523125
    }
  }

  private static func timeToSeconds(_ value: Double, unit: TimeUnit) -> Double {
    switch unit {
    case .s, .sec, .secs, .second, .seconds: value
    case .min, .mins, .minute, .minutes: value * 60
    case .h, .hr, .hrs, .hour, .hours: value * 3600
    case .d, .day, .days: value * 86400
    case .wk, .week, .weeks: value * 604_800
    }
  }

  private static func dataToBytes(_ value: Double, unit: DataUnit) -> Double {
    switch unit {
    case .b, .bit, .bits: value / 8
    case .byte, .bytes: value
    case .kb: value * 1000
    case .mb: value * 1_000_000
    case .gb: value * 1_000_000_000
    case .tb: value * 1_000_000_000_000
    case .kib: value * 1024
    case .mib: value * 1024 * 1024
    case .gib: value * 1024 * 1024 * 1024
    case .tib: value * 1024 * 1024 * 1024 * 1024
    }
  }

  private static func convertTemperature(_ value: Double, from: TemperatureUnit, to: TemperatureUnit) -> Double {
    let celsius: Double = switch from {
    case .c, .cel, .celsius: value
    case .f, .fah, .fahrenheit: (value - 32) * 5 / 9
    case .k, .kelvin: value - 273.15
    }
    return switch to {
    case .c, .cel, .celsius:
      celsius
    case .f, .fah, .fahrenheit:
      celsius * 9 / 5 + 32
    case .k, .kelvin:
      celsius + 273.15
    }
  }

  private static func format(_ value: Double, unit: UnitKind) -> String {
    let number = formatCalculatorNumber(value)
    switch unit {
    case let .length(u): return "\(number) \(display(u))"
    case let .mass(u): return "\(number) \(display(u))"
    case let .temperature(u): return "\(number) \(display(u))"
    case let .time(u): return "\(number) \(display(u))"
    case let .data(u): return "\(number) \(display(u))"
    }
  }

  private static func stripUnit(_ text: String) -> String {
    text.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? text
  }

  private static func display(_ unit: LengthUnit) -> String {
    switch unit {
    case .m: "m"
    case .km: "km"
    case .cm: "cm"
    case .mm: "mm"
    case .mi, .mile, .miles: "mi"
    case .ft, .foot, .feet: "ft"
    case .inch, .inches: "in"
    case .yd, .yard, .yards: "yd"
    }
  }

  private static func display(_ unit: MassUnit) -> String {
    switch unit {
    case .g, .gram, .grams: "g"
    case .kg, .kilogram, .kilograms: "kg"
    case .lb, .lbs, .pound, .pounds: "lb"
    case .oz, .ounce, .ounces: "oz"
    }
  }

  private static func display(_ unit: TemperatureUnit) -> String {
    switch unit {
    case .c, .cel, .celsius: "°C"
    case .f, .fah, .fahrenheit: "°F"
    case .k, .kelvin: "K"
    }
  }

  private static func display(_ unit: TimeUnit) -> String {
    switch unit {
    case .s, .sec, .secs, .second, .seconds: "s"
    case .min, .mins, .minute, .minutes: "min"
    case .h, .hr, .hrs, .hour, .hours: "h"
    case .d, .day, .days: "d"
    case .wk, .week, .weeks: "wk"
    }
  }

  private static func display(_ unit: DataUnit) -> String {
    switch unit {
    case .b, .bit, .bits: "b"
    case .byte, .bytes: "B"
    case .kb: "KB"
    case .mb: "MB"
    case .gb: "GB"
    case .tb: "TB"
    case .kib: "KiB"
    case .mib: "MiB"
    case .gib: "GiB"
    case .tib: "TiB"
    }
  }
}
