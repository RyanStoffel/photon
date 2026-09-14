import Foundation
import XCTest
@testable import PhotonNotes

@MainActor
final class NoteSidebarTests: XCTestCase {
  private let locale = Locale(identifier: "en_US")
  private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    calendar.locale = Locale(identifier: "en_US")
    return calendar
  }()

  /// Friday 2027-01-15 08:00 UTC.
  private let now = Date(timeIntervalSince1970: 1_800_000_000)

  private func note(_ id: String, _ content: String, ageInSeconds: TimeInterval = 0) -> Note {
    Note(
      id: id,
      url: URL(fileURLWithPath: "/tmp/\(id).md"),
      content: content,
      modifiedAt: now.addingTimeInterval(-ageInSeconds)
    )
  }

  private func dateText(_ date: Date) -> String {
    NoteSidebarRow.dateText(for: date, relativeTo: now, calendar: calendar, locale: locale)
  }

  // MARK: Rows

  func testRowsAreNewestFirstRegardlessOfInputOrder() {
    let notes = [
      note("old", "Old", ageInSeconds: 3600),
      note("new", "New", ageInSeconds: 0),
      note("mid", "Mid", ageInSeconds: 60)
    ]
    XCTAssertEqual(NoteSidebarRow.rows(from: notes, now: now).map(\.id), ["new", "mid", "old"])
  }

  func testEqualDatesFallBackToIdForAStableOrder() {
    let notes = [note("a", "A"), note("b", "B")]
    XCTAssertEqual(NoteSidebarRow.rows(from: notes, now: now).map(\.id), ["b", "a"])
  }

  func testRowStripsMarkdownFromTitleAndSnippet() {
    let row = NoteSidebarRow(note("n", "# Groceries\n\n- [ ] Milk\n- Eggs"), now: now)
    XCTAssertEqual(row.title, "Groceries")
    XCTAssertEqual(row.snippet, "Milk")
  }

  func testRowWithoutBodyUsesPlaceholderSnippet() {
    XCTAssertEqual(NoteSidebarRow(note("n", "Just a title"), now: now).snippet, NoteSidebarRow.emptySnippet)
    XCTAssertEqual(NoteSidebarRow(note("n", ""), now: now).title, NoteTitle.untitled)
  }

  // MARK: Date text

  func testSameDayShowsTheTime() {
    let text = dateText(now.addingTimeInterval(-2 * 3600))
    XCTAssertEqual(text.filter { !$0.isWhitespace }, "6:00AM")
  }

  func testYesterdayIsNamed() {
    XCTAssertEqual(dateText(now.addingTimeInterval(-24 * 3600)), "Yesterday")
    XCTAssertEqual(dateText(now.addingTimeInterval(-9 * 3600)), "Yesterday", "23:00 the day before counts")
  }

  func testRestOfTheWeekShowsTheWeekday() {
    XCTAssertEqual(dateText(now.addingTimeInterval(-2 * 86400)), "Wednesday")
    XCTAssertEqual(dateText(now.addingTimeInterval(-6 * 86400)), "Saturday")
  }

  func testOlderDatesAreNumeric() {
    XCTAssertEqual(dateText(now.addingTimeInterval(-7 * 86400)), "1/8/27")
    XCTAssertEqual(dateText(Date(timeIntervalSince1970: 1_787_745_600)), "8/26/26", "2026-08-26 12:00 UTC")
    XCTAssertEqual(dateText(now.addingTimeInterval(86400)), "1/16/27", "future dates are not relative")
  }

  // MARK: Model

  func testUpdateSetsRowsAndSelectionWithoutReportingASelection() {
    let model = NoteSidebarModel()
    var selected: [String] = []
    model.onSelect = { selected.append($0) }
    model.update(notes: [note("a", "A", ageInSeconds: 10), note("b", "B")], selectedID: "a", now: now)
    XCTAssertEqual(model.rows.map(\.id), ["b", "a"])
    XCTAssertEqual(model.selectedID, "a")
    XCTAssertTrue(selected.isEmpty)
  }

  func testUserSelectionIsReportedOnce() {
    let model = NoteSidebarModel()
    var selected: [String] = []
    model.onSelect = { selected.append($0) }
    model.update(notes: [note("a", "A"), note("b", "B")], selectedID: "b", now: now)
    model.selectedID = "a"
    model.selectedID = "a"
    XCTAssertEqual(selected, ["a"])
  }

  func testClearingTheSelectionKeepsTheCurrentNote() {
    let model = NoteSidebarModel()
    var selected: [String] = []
    model.onSelect = { selected.append($0) }
    model.update(notes: [note("a", "A")], selectedID: "a", now: now)
    model.selectedID = nil
    XCTAssertEqual(model.selectedID, "a")
    XCTAssertTrue(selected.isEmpty)
  }

  func testFocusRequestsCount() {
    let model = NoteSidebarModel()
    XCTAssertEqual(model.focusRequests, 0)
    model.requestFocus()
    model.requestFocus()
    XCTAssertEqual(model.focusRequests, 2)
  }
}
