import Foundation
import PhotonNotes
import XCTest

final class NoteStoreTests: XCTestCase {
  private var directory: URL!

  override func setUpWithError() throws {
    try super.setUpWithError()
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("photon-notes-tests-\(UUID().uuidString)", isDirectory: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: directory)
    try super.tearDownWithError()
  }

  func testLoadCreatesDirectoryAndStartsEmpty() throws {
    let store = NoteStore(directory: directory)
    XCTAssertTrue(try store.load().isEmpty)
    var isDirectory: ObjCBool = false
    XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory))
    XCTAssertTrue(isDirectory.boolValue)
  }

  func testCreateWritesFileNamedAfterCreationTime() throws {
    let store = NoteStore(directory: directory)
    let created = Date(timeIntervalSince1970: 1_800_000_000)
    let note = try store.create(content: "# Hello", now: created)
    XCTAssertEqual(note.url.pathExtension, "md")
    XCTAssertTrue(note.url.lastPathComponent.hasPrefix("Note 20"))
    XCTAssertTrue(note.url.lastPathComponent.contains(" at "))
    XCTAssertEqual(note.id, note.url.deletingPathExtension().lastPathComponent)
    XCTAssertEqual(try String(contentsOf: note.url, encoding: .utf8), "# Hello")
    XCTAssertEqual(store.notes.map(\.id), [note.id])
  }

  func testCreateAvoidsNameCollisions() throws {
    let store = NoteStore(directory: directory)
    let now = Date()
    let first = try store.create(now: now)
    let second = try store.create(now: now)
    XCTAssertNotEqual(first.id, second.id)
    XCTAssertTrue(second.id.hasSuffix(" 2"))
    XCTAssertEqual(store.notes.count, 2)
  }

  func testSaveWritesAtomicallyAndUpdatesNote() throws {
    let store = NoteStore(directory: directory)
    let note = try store.create(content: "old")
    let saved = try store.save(id: note.id, content: "new content")
    XCTAssertEqual(saved.content, "new content")
    XCTAssertEqual(try String(contentsOf: note.url, encoding: .utf8), "new content")
    XCTAssertEqual(store.note(id: note.id)?.content, "new content")
    let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path)
    XCTAssertEqual(leftovers, [note.url.lastPathComponent], "atomic write must not leave temp files behind")
  }

  func testSaveUnknownNoteThrows() {
    let store = NoteStore(directory: directory)
    XCTAssertThrowsError(try store.save(id: "missing", content: "x")) { error in
      XCTAssertEqual(error as? NoteStoreError, .unknownNote("missing"))
    }
  }

  func testLoadReadsExistingMarkdownFilesAndSortsByModifiedDate() throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let older = directory.appendingPathComponent("older.md")
    let newer = directory.appendingPathComponent("newer.markdown")
    let ignored = directory.appendingPathComponent("ignored.txt")
    try Data("# Older".utf8).write(to: older)
    try Data("# Newer".utf8).write(to: newer)
    try Data("nope".utf8).write(to: ignored)
    try FileManager.default.setAttributes(
      [.modificationDate: Date(timeIntervalSinceNow: -3600)],
      ofItemAtPath: older.path
    )

    let store = NoteStore(directory: directory)
    let notes = try store.load()
    XCTAssertEqual(notes.map(\.id), ["newer", "older"])
    XCTAssertEqual(notes.map(\.title), ["Newer", "Older"])
  }

  func testRescanDetectsExternalAddUpdateAndRemove() throws {
    let store = NoteStore(directory: directory)
    let kept = try store.create(content: "keep")
    let changed = try store.create(content: "before")
    let removed = try store.create(content: "gone")

    try Data("after".utf8).write(to: changed.url)
    try FileManager.default.setAttributes(
      [.modificationDate: Date(timeIntervalSinceNow: 60)],
      ofItemAtPath: changed.url.path
    )
    try FileManager.default.removeItem(at: removed.url)
    let addedURL = directory.appendingPathComponent("external.md")
    try Data("# External".utf8).write(to: addedURL)

    let changes = try store.rescan()
    XCTAssertEqual(changes.added, ["external"])
    XCTAssertEqual(changes.updated, [changed.id])
    XCTAssertEqual(changes.removed, [removed.id])
    XCTAssertEqual(store.note(id: changed.id)?.content, "after")
    XCTAssertNil(store.note(id: removed.id))
    XCTAssertEqual(store.note(id: kept.id)?.content, "keep")
    XCTAssertEqual(store.note(id: "external")?.title, "External")
    XCTAssertTrue(try store.rescan().isEmpty, "a second scan with no changes reports nothing")
  }

  func testOwnSavesDoNotShowUpAsExternalChanges() throws {
    let store = NoteStore(directory: directory)
    let note = try store.create(content: "a")
    try store.save(id: note.id, content: "b")
    XCTAssertTrue(try store.rescan().isEmpty)
  }

  func testDeleteRemovesNote() throws {
    let store = NoteStore(directory: directory)
    let note = try store.create(content: "bye")
    try store.delete(id: note.id)
    XCTAssertNil(store.note(id: note.id))
    XCTAssertTrue(store.notes.isEmpty)
    XCTAssertThrowsError(try store.delete(id: note.id))
  }

  func testChangesIsEmptyOnlyWhenNothingChanged() {
    XCTAssertTrue(NoteStoreChanges().isEmpty)
    XCTAssertFalse(NoteStoreChanges(updated: ["x"]).isEmpty)
  }
}
