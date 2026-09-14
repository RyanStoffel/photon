import PhotonCore
import XCTest

final class CalculatorDisplayModelTests: XCTestCase {
  func testMathResultMapsToHeroModel() {
    let result = CalculatorEngine.evaluate("2 + 2")
    let model = CalculatorDisplayModel(result: XCTUnwrap(result), commandID: "calculator:test")
    XCTAssertEqual(model.expression, "2 + 2")
    XCTAssertEqual(model.value, "4")
    XCTAssertEqual(model.expressionCaption, "Sum")
    XCTAssertEqual(model.valueCaption, "Four")
  }

  func testConversionMapsExpressionAndValue() {
    let result = CalculatorEngine.evaluate("10 km to mi")
    let model = CalculatorDisplayModel(result: XCTUnwrap(result), commandID: "calculator:convert")
    XCTAssertEqual(model.expressionCaption, "Convert")
    XCTAssertFalse(model.expression.isEmpty)
    XCTAssertFalse(model.value.isEmpty)
  }

  func testSectionTitle() {
    XCTAssertEqual(CalculatorDisplayModel.sectionTitle, "Calculator")
  }
}
