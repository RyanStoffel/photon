import Foundation

/// Raycast-style calculator hero card content derived from an evaluated result.
public struct CalculatorDisplayModel: Equatable, Sendable {
  public let commandID: String
  public let expression: String
  public let value: String
  public let expressionCaption: String
  public let valueCaption: String?

  public init(
    commandID: String,
    expression: String,
    value: String,
    expressionCaption: String,
    valueCaption: String? = nil
  ) {
    self.commandID = commandID
    self.expression = expression
    self.value = value
    self.expressionCaption = expressionCaption
    self.valueCaption = valueCaption
  }

  public init(result: CalculatorResult, commandID: String) {
    self.init(
      commandID: commandID,
      expression: result.expression,
      value: result.value,
      expressionCaption: result.operationLabel,
      valueCaption: result.wordForm
    )
  }

  public static let sectionTitle = "Calculator"
}
