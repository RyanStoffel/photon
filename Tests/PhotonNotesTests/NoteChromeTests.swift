import Foundation
import PhotonNotes
import XCTest

final class NoteActionTests: XCTestCase {
  func testCatalogIncludesRaycastStyleActions() {
    let ids = NoteAction.catalog.map(\.id)
    XCTAssertEqual(
      ids,
      [
        .newNote,
        .duplicateNote,
        .browseNotes,
        .findInNote,
        .copyNote,
        .copyDeepLink,
        .exportNote,
        .moveListItemUp,
        .moveListItemDown,
        .format,
      ]
    )
  }

  func testMatchingFiltersByTitleAndKeywords() {
    XCTAssertEqual(NoteAction.matching("").count, NoteAction.catalog.count)
    XCTAssertEqual(NoteAction.matching("deeplink").map(\.id), [.copyDeepLink])
    XCTAssertEqual(NoteAction.matching("export").map(\.id), [.exportNote])
    XCTAssertTrue(NoteAction.matching("zzzz").isEmpty)
  }
}

final class NoteDeepLinkTests: XCTestCase {
  func testRoundTrip() throws {
    let url = try XCTUnwrap(NoteDeepLink.url(for: "Note 2026-09-18 at 01.00.00"))
    XCTAssertEqual(url.scheme, "photon")
    XCTAssertEqual(url.host, "note")
    XCTAssertEqual(NoteDeepLink.noteID(from: url), "Note 2026-09-18 at 01.00.00")
  }

  func testRejectsOtherSchemes() {
    XCTAssertNil(NoteDeepLink.noteID(from: URL(string: "https://example.com/note/x")!))
    XCTAssertNil(NoteDeepLink.noteID(from: URL(string: "photon://other/x")!))
  }
}

final class NotePinStoreTests: XCTestCase {
  func testToggleAndPersist() {
    let suite = "photon-pin-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    var store = NotePinStore(defaults: defaults)
    XCTAssertFalse(store.isPinned("a"))
    store.toggle("a")
    store.save(to: defaults)
    XCTAssertTrue(NotePinStore(defaults: defaults).isPinned("a"))
    store.toggle("a")
    XCTAssertFalse(store.isPinned("a"))
  }
}

final class NoteSwitcherItemTests: XCTestCase {
  func testSwitcherPutsPinnedNotesFirstAndMarksCurrent() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let notes = [
      Note(
        id: "b",
        url: URL(fileURLWithPath: "/tmp/b.md"),
        content: "Second",
        modifiedAt: now
      ),
      Note(
        id: "a",
        url: URL(fileURLWithPath: "/tmp/a.md"),
        content: "First",
        modifiedAt: now.addingTimeInterval(-60)
      ),
    ]
    let items = NoteSwitcherItem.items(from: notes, currentID: "a", pinned: ["a"], now: now)
    XCTAssertEqual(items.map(\.id), ["a", "b"])
    XCTAssertTrue(items[0].isCurrent)
    XCTAssertTrue(items[0].isPinned)
    XCTAssertTrue(items[0].subtitle.hasPrefix("Current"))
  }
}
