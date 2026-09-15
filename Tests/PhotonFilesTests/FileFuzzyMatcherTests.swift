import XCTest
@testable import PhotonFiles

final class FileFuzzyMatcherTests: XCTestCase {
  func testSeparatorsAreIgnored() {
    XCTAssertTrue(FileFuzzyMatcher.matches(query: "ember_individual", candidate: "Ember_Individual_Pitch"))
    XCTAssertTrue(FileFuzzyMatcher.matches(query: "ember individual", candidate: "Ember_Individual_Pitch"))
  }

  func testSubsequenceMatching() {
    XCTAssertNotNil(FileFuzzyMatcher.score(query: "eip", candidate: "Ember_Individual_Pitch"))
  }

  func testNoMatchReturnsNil() {
    XCTAssertNil(FileFuzzyMatcher.score(query: "zzzz", candidate: "Ember_Individual_Pitch"))
  }
}
