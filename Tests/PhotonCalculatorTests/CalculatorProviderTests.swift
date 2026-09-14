import PhotonCalculator
import XCTest

final class CalculatorProviderTests: XCTestCase {
  func testCommandRoundTrip() async throws {
    let provider = CalculatorProvider()
    let commands = await provider.commands(matching: "1+1")
    XCTAssertEqual(commands.count, 1)
    XCTAssertEqual(commands[0].title, "1+1 → 2")
    let restored = CalculatorProvider.query(fromCommandID: commands[0].id)
    XCTAssertEqual(restored, "1+1")
  }
}
