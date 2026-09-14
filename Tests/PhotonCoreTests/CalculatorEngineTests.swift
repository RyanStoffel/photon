import PhotonCore
import XCTest

final class CalculatorEngineTests: XCTestCase {
  func testDivisionShowsDivideLabel() {
    let result = CalculatorEngine.evaluate("30/5")
    XCTAssertEqual(result?.value, "6")
    XCTAssertEqual(result?.operationLabel, "Divide")
    XCTAssertEqual(result?.wordForm, "Six")
    XCTAssertEqual(result?.rowTitle, "30/5 → 6")
  }

  func testParenthesesAndPower() {
    XCTAssertEqual(CalculatorEngine.evaluate("(2+3)*4")?.value, "20")
    XCTAssertEqual(CalculatorEngine.evaluate("2^10")?.value, "1024")
    XCTAssertEqual(CalculatorEngine.evaluate("2^10")?.operationLabel, "Power")
  }

  func testDecimalsAndModulo() {
    XCTAssertEqual(CalculatorEngine.evaluate("3.5 * 2")?.value, "7")
    XCTAssertEqual(CalculatorEngine.evaluate("10 % 3")?.value, "1")
  }

  func testLengthConversion() throws {
    let result = try XCTUnwrap(CalculatorEngine.evaluate("10 km to mi"))
    XCTAssertEqual(result.operationLabel, "Convert")
    XCTAssertTrue(result.rowTitle.contains("→"))
  }

  func testTemperatureConversion() {
    let freezing = CalculatorEngine.evaluate("32 f to c")
    XCTAssertEqual(freezing?.value, "0")
    let boiling = CalculatorEngine.evaluate("212 f to c")
    XCTAssertEqual(boiling?.value, "100")
  }

  func testDataConversion() {
    let result = CalculatorEngine.evaluate("1024 mb to gb")
    XCTAssertNotNil(result)
  }

  func testNonExpressionReturnsNil() {
    XCTAssertNil(CalculatorEngine.evaluate("safari"))
    XCTAssertNil(CalculatorEngine.evaluate(""))
    XCTAssertNil(CalculatorEngine.evaluate("1/0"))
  }
}
