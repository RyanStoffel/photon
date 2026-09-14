import Foundation
import PhotonNotes
import XCTest

final class NoteTitleTests: XCTestCase {
  func testHeadingMarkerIsStripped() {
    XCTAssertEqual(NoteTitle.extract(from: "# Grocery list\n- Milk"), "Grocery list")
    XCTAssertEqual(NoteTitle.extract(from: "###   Deep heading"), "Deep heading")
  }

  func testLeadingBlankLinesAreSkipped() {
    XCTAssertEqual(NoteTitle.extract(from: "\n\n   \nMeeting notes\nbody"), "Meeting notes")
  }

  func testEmptyContentIsUntitled() {
    XCTAssertEqual(NoteTitle.extract(from: ""), NoteTitle.untitled)
    XCTAssertEqual(NoteTitle.extract(from: "  \n\t\n"), NoteTitle.untitled)
    XCTAssertEqual(NoteTitle.extract(from: "# "), NoteTitle.untitled)
  }

  func testListAndCheckboxMarkersAreStripped() {
    XCTAssertEqual(NoteTitle.extract(from: "- [ ] Buy milk"), "Buy milk")
    XCTAssertEqual(NoteTitle.extract(from: "1. First step"), "First step")
    XCTAssertEqual(NoteTitle.extract(from: "* Bullet"), "Bullet")
    XCTAssertEqual(NoteTitle.extract(from: "> Quoted"), "Quoted")
  }

  func testWrappingEmphasisIsStripped() {
    XCTAssertEqual(NoteTitle.extract(from: "**Bold title**"), "Bold title")
    XCTAssertEqual(NoteTitle.extract(from: "`code`"), "code")
    XCTAssertEqual(NoteTitle.extract(from: "snake_case_title"), "snake_case_title")
  }

  func testWhitespaceIsCollapsed() {
    XCTAssertEqual(NoteTitle.extract(from: "  Two   spaces\t here  "), "Two spaces here")
  }

  func testLongTitleIsTruncatedWithEllipsis() {
    let title = NoteTitle.extract(from: String(repeating: "a", count: 200))
    XCTAssertEqual(title.count, NoteTitle.maxTitleLength)
    XCTAssertTrue(title.hasSuffix("…"))
  }

  func testPreviewUsesSecondNonBlankLine() {
    XCTAssertEqual(NoteTitle.preview(from: "# Title\n\n- [x] Done item\nmore"), "Done item")
    XCTAssertEqual(NoteTitle.preview(from: "Only a title"), "")
    XCTAssertEqual(NoteTitle.preview(from: ""), "")
  }

  func testNoteExposesTitlePreviewAndBlankness() {
    let url = URL(fileURLWithPath: "/tmp/example.md")
    let note = Note(id: "example", url: url, content: "Hello\nWorld", modifiedAt: Date())
    XCTAssertEqual(note.title, "Hello")
    XCTAssertEqual(note.preview, "World")
    XCTAssertFalse(note.isBlank)
    XCTAssertTrue(Note(id: "b", url: url, content: " \n", modifiedAt: Date()).isBlank)
    let summary = NoteSummary(note)
    XCTAssertEqual(summary.id, "example")
    XCTAssertEqual(summary.title, "Hello")
  }
}
