import PhotonCalculator
import PhotonCore

extension LauncherViewModel {
  /// When the top result is a calculator match, show the Raycast-style hero card instead of a list row.
  var calculatorHero: CalculatorDisplayModel? {
    guard showsCommandList, let command = results.first?.command, command.providerID == "calculator" else {
      return nil
    }
    guard let query = CalculatorProvider.query(fromCommandID: command.id),
          let result = CalculatorEngine.evaluate(query)
    else {
      return nil
    }
    return CalculatorDisplayModel(result: result, commandID: command.id)
  }

  var rowsBelowCalculatorHero: [LauncherRow] {
    guard calculatorHero != nil else {
      return rows
    }
    return Array(rows.dropFirst())
  }
}
