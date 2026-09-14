import XCTest
@testable import PhotonFiles

final class MdfindInvocationTests: XCTestCase {
  func testHomeScopeUsesOnlyInThenNullTerminatedQuery() {
    XCTAssertEqual(
      MdfindInvocation.arguments(queryString: "kMDItemFSName == \"*ember*\"cd", onlyIn: ["/Users/ryan"]),
      ["-onlyin", "/Users/ryan", "-0", "kMDItemFSName == \"*ember*\"cd"]
    )
  }

  func testComputerScopeOmitsOnlyIn() {
    XCTAssertEqual(
      MdfindInvocation.arguments(queryString: "report", onlyIn: []),
      ["-0", "report"]
    )
  }

  func testExtraFoldersBecomeAdditionalOnlyIn() {
    let args = MdfindInvocation.arguments(
      queryString: "pitch",
      onlyIn: ["/Users/ryan", "/Volumes/Projects"]
    )
    XCTAssertEqual(
      args,
      ["-onlyin", "/Users/ryan", "-onlyin", "/Volumes/Projects", "-0", "pitch"]
    )
  }

  func testNameSearchUsesDashNameThenNullTerminatedOutput() {
    XCTAssertEqual(
      MdfindInvocation.nameArguments(fileName: "ember", onlyIn: ["/Users/ryan"]),
      ["-onlyin", "/Users/ryan", "-name", "ember", "-0", "ember"]
    )
  }

  func testNullTerminatedPathsRespectLimit() {
    let data = Data("/Users/ryan/a.pdf\0/Users/ryan/b.pdf\0/Users/ryan/c.pdf\0".utf8)
    XCTAssertEqual(
      MdfindInvocation.paths(fromNullTerminated: data, limit: 2),
      ["/Users/ryan/a.pdf", "/Users/ryan/b.pdf"]
    )
  }

  func testTrailingPathWithoutNulIsKept() {
    let data = Data("/Users/ryan/Ember_Individual_Pitch.pdf".utf8)
    XCTAssertEqual(
      MdfindInvocation.paths(fromNullTerminated: data, limit: 10),
      ["/Users/ryan/Ember_Individual_Pitch.pdf"]
    )
  }
}
