import PhotonNotes
import XCTest

final class NotesLayoutTests: XCTestCase {
  func testPanelWidthIsFixedAndNarrowerThanTheRegularLauncher() {
    XCTAssertEqual(NotesLayout.panelWidth, 680)
    XCTAssertLessThan(NotesLayout.panelWidth, 760, "Regular launcher width")
    XCTAssertGreaterThan(NotesLayout.panelWidth, 640)
    XCTAssertLessThan(NotesLayout.panelWidth, 700)
  }

  func testConstrainedSizeKeepsWidthConstantWhenHeightChanges() {
    let taller = NotesLayout.constrainedSize(from: CGSize(width: 1200, height: 900))
    let shorter = NotesLayout.constrainedSize(from: CGSize(width: 200, height: 100))
    XCTAssertEqual(taller.width, NotesLayout.panelWidth)
    XCTAssertEqual(shorter.width, NotesLayout.panelWidth)
    XCTAssertEqual(taller.height, 900)
    XCTAssertEqual(shorter.height, NotesLayout.minimumHeight)
  }

  func testDefaultSizeUsesTheConstantWidth() {
    XCTAssertEqual(NotesLayout.defaultSize.width, NotesLayout.panelWidth)
    XCTAssertEqual(NotesLayout.minimumSize.width, NotesLayout.panelWidth)
    XCTAssertGreaterThan(NotesLayout.defaultSize.height, NotesLayout.minimumHeight)
  }

  func testCharacterCountCopy() {
    XCTAssertEqual(NotesLayout.characterCountLabel(0, capitalized: false), "0 characters")
    XCTAssertEqual(NotesLayout.characterCountLabel(0, capitalized: true), "0 Characters")
    XCTAssertEqual(NotesLayout.characterCountLabel(1, capitalized: false), "1 character")
    XCTAssertEqual(NotesLayout.characterCountLabel(206, capitalized: true), "206 Characters")
  }
}
