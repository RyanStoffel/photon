import Foundation
import XCTest
@testable import PhotonFiles

final class FileSystemFallbackSearchTests: XCTestCase {
  func testFindsUnindexedDocumentByBasename() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let document = root
      .appendingPathComponent("Documents/School/Capstone/Individual Pitch", isDirectory: true)
      .appendingPathComponent("Ember_Individual_Pitch.pdf")
    try FileManager.default.createDirectory(
      at: document.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try Data("fixture".utf8).write(to: document)
    defer { try? FileManager.default.removeItem(at: root) }

    XCTAssertEqual(
      FileSystemFallbackSearch.paths(
        matching: "ember",
        home: root.path,
        extraFolders: [],
        resultLimit: 20
      ),
      [document.path]
    )
  }

  func testRespectsResultLimitAndIgnoresLibrary() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let documents = root.appendingPathComponent("Documents", isDirectory: true)
    let library = root.appendingPathComponent("Library", isDirectory: true)
    try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
    try Data().write(to: documents.appendingPathComponent("ember-one.pdf"))
    try Data().write(to: documents.appendingPathComponent("ember-two.pdf"))
    try Data().write(to: library.appendingPathComponent("ember-secret.pdf"))
    defer { try? FileManager.default.removeItem(at: root) }

    let matches = FileSystemFallbackSearch.paths(
      matching: "ember",
      home: root.path,
      extraFolders: [],
      resultLimit: 1
    )
    XCTAssertEqual(matches.count, 1)
    XCTAssertTrue(matches[0].hasPrefix(documents.path))
  }
}
