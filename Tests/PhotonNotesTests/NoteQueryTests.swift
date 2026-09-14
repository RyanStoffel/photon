import Foundation
import PhotonNotes
import XCTest

final class NoteQueryTests: XCTestCase {
  func testBareWordsListEverything() {
    XCTAssertEqual(NoteQuery.parse("note"), .list(filter: ""))
    XCTAssertEqual(NoteQuery.parse("notes"), .list(filter: ""))
    XCTAssertEqual(NoteQuery.parse("Notes "), .list(filter: ""))
    XCTAssertEqual(NoteQuery.parse("n "), .list(filter: ""))
  }

  func testPrefixedTextBecomesFilter() {
    XCTAssertEqual(NoteQuery.parse("n groceries"), .list(filter: "groceries"))
    XCTAssertEqual(NoteQuery.parse("note Meeting"), .list(filter: "meeting"))
    XCTAssertEqual(NoteQuery.parse("notes   two words "), .list(filter: "two words"))
  }

  func testUnrelatedQueries() {
    XCTAssertEqual(NoteQuery.parse(""), .unrelated)
    XCTAssertEqual(NoteQuery.parse("n"), .unrelated)
    XCTAssertEqual(NoteQuery.parse("notebook"), .unrelated)
    XCTAssertEqual(NoteQuery.parse("safari"), .unrelated)
    XCTAssertEqual(NoteQuery.parse("nothing"), .unrelated)
  }

  func testKeywordsCoverEveryPrefix() {
    XCTAssertEqual(NoteQuery.keywords(forTitle: "Plan"), ["notes Plan", "note Plan", "n Plan"])
  }
}
