import XCTest
@testable import PhotonFiles

@MainActor
final class FileSearchControllerSessionTests: XCTestCase {
  func testEmptyUpdateDuringGrantResumeKeepsThePendingQuery() {
    let controller = FileSearchController()
    controller.resumeAfterAccess(query: "ember")
    XCTAssertEqual(controller.currentQuery, "ember")
    controller.update(query: "")
    XCTAssertEqual(controller.currentQuery, "ember")
  }

  func testClearResumeProtectionAllowsAnEmptyRecentsSession() {
    let controller = FileSearchController()
    controller.resumeAfterAccess(query: "ember")
    XCTAssertEqual(controller.currentQuery, "ember")
    controller.clearResumeProtection()
    controller.deactivate()
    XCTAssertEqual(controller.currentQuery, "")
    controller.activate(query: "")
    XCTAssertEqual(controller.currentQuery, "")
  }
}
