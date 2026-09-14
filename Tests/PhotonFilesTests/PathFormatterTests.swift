import XCTest
@testable import PhotonFiles

final class PathFormatterTests: XCTestCase {
  private let home = "/Users/ryan"

  func testHomeIsAbbreviated() {
    XCTAssertEqual(PathFormatter.abbreviatingHome("/Users/ryan/Documents/a.txt", home: home), "~/Documents/a.txt")
    XCTAssertEqual(PathFormatter.abbreviatingHome("/Users/ryan", home: home), "~")
    XCTAssertEqual(PathFormatter.abbreviatingHome("/Users/ryan/", home: "/Users/ryan/"), "~/")
  }

  func testOtherUsersAndSystemPathsAreNotAbbreviated() {
    XCTAssertEqual(PathFormatter.abbreviatingHome("/Users/ryanb/x", home: home), "/Users/ryanb/x")
    XCTAssertEqual(PathFormatter.abbreviatingHome("/Applications", home: home), "/Applications")
  }

  func testShortPathsAreUntouched() {
    XCTAssertEqual(PathFormatter.middleTruncated("~/Documents", maxLength: 20), "~/Documents")
    XCTAssertEqual(PathFormatter.middleTruncated("~/Documents", maxLength: 11), "~/Documents")
  }

  func testMiddleComponentsAreDroppedFirst() {
    let path = "~/Documents/Projects/Photon/Sources/Photon/Launcher"
    XCTAssertEqual(PathFormatter.middleTruncated(path, maxLength: 32), "~/…/Sources/Photon/Launcher")
    XCTAssertEqual(PathFormatter.middleTruncated(path, maxLength: 34), "~/…/Photon/Sources/Photon/Launcher")
  }

  func testRootAndLastComponentSurvive() {
    let path = "/Volumes/External/Archive/2024/Photos/Trip/IMG_0001.HEIC"
    let truncated = PathFormatter.middleTruncated(path, maxLength: 28)
    XCTAssertTrue(truncated.hasPrefix("/Volumes/…/"))
    XCTAssertTrue(truncated.hasSuffix("/IMG_0001.HEIC"))
    XCTAssertLessThanOrEqual(truncated.count, 28)
  }

  func testSingleLongComponentFallsBackToCharacterTruncation() {
    let name = String(repeating: "a", count: 40) + ".txt"
    let truncated = PathFormatter.middleTruncated(name, maxLength: 15)
    XCTAssertEqual(truncated.count, 15)
    XCTAssertTrue(truncated.contains(PathFormatter.ellipsis))
    XCTAssertTrue(truncated.hasSuffix("a.txt"))
  }

  func testTruncationNeverExceedsBudget() {
    let path = "/Users/ryan/Library/Application Support/Photon/Notes/Very Long Note Title Goes Here.md"
    for budget in 1 ... path.count {
      XCTAssertLessThanOrEqual(PathFormatter.middleTruncated(path, maxLength: budget).count, budget)
    }
  }

  func testParentDisplayAbbreviatesAndTruncates() {
    let display = PathFormatter.parentDisplay(
      for: "/Users/ryan/Documents/Projects/Photon/README.md",
      maxLength: 24,
      home: home
    )
    XCTAssertEqual(display, "~/…/Projects/Photon")
    XCTAssertEqual(PathFormatter.parentDisplay(for: "/README.md", home: home), "/")
  }
}
