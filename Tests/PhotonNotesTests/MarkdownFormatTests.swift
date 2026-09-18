import Foundation
import PhotonNotes
import XCTest

final class MarkdownFormatTests: XCTestCase {
  func testBoldWrapsTheSelection() {
    let edit = MarkdownFormat.apply(.bold, to: "hello world", selection: NSRange(location: 6, length: 5))
    XCTAssertEqual(edit.text, "hello **world**")
    XCTAssertEqual(edit.selection, NSRange(location: 8, length: 5))
  }

  func testEmptySelectionInsertsMarkers() {
    let edit = MarkdownFormat.apply(.italic, to: "ab", selection: NSRange(location: 1, length: 0))
    XCTAssertEqual(edit.text, "a**b")
    XCTAssertEqual(edit.selection.location, 2)
    XCTAssertEqual(edit.selection.length, 0)
  }

  func testHeadingReplacesExistingMarker() {
    let edit = MarkdownFormat.apply(.heading(2), to: "# Title", selection: NSRange(location: 2, length: 0))
    XCTAssertEqual(edit.text, "## Title")
  }

  func testChecklistPrefixesTheLine() {
    let edit = MarkdownFormat.apply(.checklist, to: "Buy milk", selection: NSRange(location: 0, length: 0))
    XCTAssertEqual(edit.text, "- [ ] Buy milk")
  }

  func testMoveListItemDownSwapsNeighbors() {
    let text = "- one\n- two\n- three"
    let fromStart = MarkdownFormat.moveListItem(in: text, at: 0, by: 1)
    XCTAssertEqual(fromStart?.text, "- two\n- one\n- three")
    let fromMiddle = MarkdownFormat.moveListItem(in: text, at: 3, by: 1)
    XCTAssertEqual(fromMiddle?.text, "- two\n- one\n- three")
    let secondDown = MarkdownFormat.moveListItem(in: text, at: 8, by: 1)
    XCTAssertEqual(secondDown?.text, "- one\n- three\n- two")
  }

  func testMoveListItemStopsAtTheListEdge() {
    XCTAssertNil(MarkdownFormat.moveListItem(in: "- only", at: 0, by: -1))
    XCTAssertNil(MarkdownFormat.moveListItem(in: "plain", at: 0, by: 1))
  }

  func testLinkWrapsTheSelection() {
    let edit = MarkdownFormat.apply(.link, to: "Photon", selection: NSRange(location: 0, length: 6))
    XCTAssertEqual(edit.text, "[Photon](url)")
  }
}
