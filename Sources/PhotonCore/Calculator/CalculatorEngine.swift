import Foundation

/// Local calculator and unit conversion for the launcher. No network, no AI.
public enum CalculatorEngine: Sendable {
  /// Returns a result when `query` is a math expression or supported conversion.
  public static func evaluate(_ rawQuery: String) -> CalculatorResult? {
    let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else {
      return nil
    }
    if let conversion = UnitConversion.evaluate(query) {
      return conversion
    }
    return MathExpression.evaluate(query)
  }
}
