import XCTest
@testable import PhotonFiles

final class SpotlightQueryBuilderTests: XCTestCase {
  func testEmptyQueryProducesNoQueryString() {
    XCTAssertNil(SpotlightQueryBuilder.queryString(for: "", searchContents: false))
    XCTAssertNil(SpotlightQueryBuilder.queryString(for: "   \n", searchContents: true))
  }

  func testTermsSplitOnWhitespaceAndDedupeCaseInsensitively() {
    XCTAssertEqual(SpotlightQueryBuilder.terms(from: "  annual\treport Report\n"), ["annual", "report"])
  }

  func testTermsSplitOnUnderscoresAndPunctuation() {
    XCTAssertEqual(SpotlightQueryBuilder.terms(from: "ember_individual"), ["ember", "individual"])
    XCTAssertEqual(
      SpotlightQueryBuilder.terms(from: "Ember-Individual-Pitch.pdf"),
      ["Ember", "Individual", "Pitch", "pdf"]
    )
  }

  func testLongTermMatchesAnywhereInNameAndFileName() {
    let query = SpotlightQueryBuilder.queryString(for: "report", searchContents: false)
    XCTAssertEqual(
      query,
      "(kMDItemDisplayName == \"*report*\"cd || kMDItemFSName == \"*report*\"cd)"
    )
  }

  func testShortTermOnlyMatchesWordPrefixes() {
    let query = SpotlightQueryBuilder.queryString(for: "ab", searchContents: false)
    XCTAssertEqual(query, "(kMDItemDisplayName == \"ab*\"cdw || kMDItemFSName == \"ab*\"cdw)")
  }

  func testUnderscoreQueryBecomesAndOfNameClauses() {
    let query = SpotlightQueryBuilder.queryString(for: "ember_individual", searchContents: false)
    XCTAssertEqual(
      query,
      "(kMDItemDisplayName == \"*ember*\"cd || kMDItemFSName == \"*ember*\"cd)"
        + " && (kMDItemDisplayName == \"*individual*\"cd || kMDItemFSName == \"*individual*\"cd)"
    )
  }

  func testEveryTermMustMatch() {
    let query = SpotlightQueryBuilder.queryString(for: "annual report", searchContents: false)
    XCTAssertEqual(
      query,
      "(kMDItemDisplayName == \"*annual*\"cd || kMDItemFSName == \"*annual*\"cd)"
        + " && (kMDItemDisplayName == \"*report*\"cd || kMDItemFSName == \"*report*\"cd)"
    )
  }

  func testContentSearchAddsTextContentClause() {
    let query = SpotlightQueryBuilder.queryString(for: "invoice", searchContents: true)
    XCTAssertEqual(
      query,
      "(kMDItemDisplayName == \"*invoice*\"cd || kMDItemFSName == \"*invoice*\"cd"
        + " || kMDItemTextContent == \"invoice*\"cdw)"
    )
  }

  func testEscapesQuotesBackslashesAndWildcards() {
    XCTAssertEqual(SpotlightQueryBuilder.escape("a\"b"), "a\\\"b")
    XCTAssertEqual(SpotlightQueryBuilder.escape("a\\b"), "a\\\\b")
    XCTAssertEqual(SpotlightQueryBuilder.escape("a*b?"), "a\\*b\\?")
    let query = SpotlightQueryBuilder.queryString(for: "say \"hi\"", searchContents: false)
    XCTAssertEqual(
      query,
      "(kMDItemDisplayName == \"*say*\"cd || kMDItemFSName == \"*say*\"cd)"
        + " && (kMDItemDisplayName == \"*hi*\"cd || kMDItemFSName == \"*hi*\"cd)"
    )
  }
}
