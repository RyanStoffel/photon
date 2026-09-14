import PhotonCore
import XCTest

final class CommandIconTests: XCTestCase {
  func testCommandsHaveNoIconUnlessTheProviderSetsOne() {
    let command = Command(id: "x", title: "X", providerID: "test")
    XCTAssertNil(command.icon)
  }

  func testCommandKeepsTheIconItWasGiven() {
    let command = Command(
      id: "app:com.apple.Safari",
      title: "Safari",
      providerID: "apps",
      icon: .fileIcon(path: "/Applications/Safari.app")
    )
    XCTAssertEqual(command.icon, .fileIcon(path: "/Applications/Safari.app"))
  }

  func testIconTakesPartInEquality() {
    let plain = Command(id: "x", title: "X", providerID: "test")
    let withSymbol = Command(id: "x", title: "X", providerID: "test", icon: .symbol(name: "clipboard"))
    XCTAssertNotEqual(plain, withSymbol)
    XCTAssertEqual(withSymbol, Command(id: "x", title: "X", providerID: "test", icon: .symbol(name: "clipboard")))
  }

  func testDifferentSourcesForTheSamePathAreDistinct() {
    XCTAssertNotEqual(CommandIcon.fileIcon(path: "/a.icns"), CommandIcon.imageFile(path: "/a.icns"))
  }
}
