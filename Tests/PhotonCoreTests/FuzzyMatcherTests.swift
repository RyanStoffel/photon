import PhotonCore
import XCTest

final class FuzzyMatcherTests: XCTestCase {
  func testEmptyQueryMatchesEverything() {
    XCTAssertEqual(FuzzyMatcher.score(query: "", candidate: "Safari"), 1)
    XCTAssertTrue(FuzzyMatcher.matches(query: "", candidate: "Xcode"))
  }

  func testSubsequenceMatchIsCaseInsensitive() {
    XCTAssertNotNil(FuzzyMatcher.score(query: "xcd", candidate: "Xcode"))
    XCTAssertNotNil(FuzzyMatcher.score(query: "SF", candidate: "Safari"))
    XCTAssertNotNil(FuzzyMatcher.score(query: "sysset", candidate: "System Settings"))
  }

  func testNonSubsequenceDoesNotMatch() {
    XCTAssertNil(FuzzyMatcher.score(query: "zzz", candidate: "Safari"))
    XCTAssertNil(FuzzyMatcher.score(query: "code", candidate: "Safari"))
    XCTAssertFalse(FuzzyMatcher.matches(query: "qq", candidate: "Notes"))
  }

  func testExactMatchOutranksPartial() {
    let exact = FuzzyMatcher.score(query: "Xcode", candidate: "Xcode")
    let partial = FuzzyMatcher.score(query: "Xcode", candidate: "Xcode Helper")
    XCTAssertNotNil(exact)
    XCTAssertNotNil(partial)
    XCTAssertGreaterThan(exact ?? 0, partial ?? 0)
  }

  func testPrefixOutranksLaterOccurrence() {
    let prefix = FuzzyMatcher.score(query: "cal", candidate: "Calculator")
    let later = FuzzyMatcher.score(query: "cal", candidate: "Local Calendar")
    XCTAssertNotNil(prefix)
    XCTAssertNotNil(later)
    XCTAssertGreaterThan(prefix ?? 0, later ?? 0)
  }

  func testConsecutiveCharactersBeatScattered() {
    let tight = FuzzyMatcher.score(query: "xc", candidate: "Xcode")
    let loose = FuzzyMatcher.score(query: "xc", candidate: "Xerox Copier")
    XCTAssertNotNil(tight)
    XCTAssertNotNil(loose)
    XCTAssertGreaterThan(tight ?? 0, loose ?? 0)
  }

  func testWordStartIsRewarded() {
    let word = FuzzyMatcher.score(query: "ss", candidate: "System Settings")
    let buried = FuzzyMatcher.score(query: "ss", candidate: "Classics")
    XCTAssertNotNil(word)
    XCTAssertNotNil(buried)
    XCTAssertGreaterThan(word ?? 0, buried ?? 0)
  }

  func testEmptyCandidateRejectsNonEmptyQuery() {
    XCTAssertNil(FuzzyMatcher.score(query: "a", candidate: ""))
  }
}
