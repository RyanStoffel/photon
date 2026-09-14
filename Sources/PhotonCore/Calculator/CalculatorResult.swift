import Foundation

/// Outcome of parsing and evaluating a launcher calculator query.
public struct CalculatorResult: Equatable, Sendable {
  public let expression: String
  public let value: String
  public let operationLabel: String
  public let wordForm: String?

  public init(expression: String, value: String, operationLabel: String, wordForm: String? = nil) {
    self.expression = expression
    self.value = value
    self.operationLabel = operationLabel
    self.wordForm = wordForm
  }

  /// Row title: expression, arrow, formatted result (Raycast-style, one line).
  public var rowTitle: String {
    "\(expression) → \(value)"
  }

  /// Text copied when the user presses Enter.
  public var copyValue: String {
    value
  }
}
