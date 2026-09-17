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

    let matches = FileSystemFallbackSearch.paths(
      matching: "ember",
      roots: [root.appendingPathComponent("Documents").path],
      home: root.path,
      resultLimit: 20
    )
    XCTAssertEqual(matches.map(resolvedPath), [resolvedPath(document.path)])
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
      roots: [root.path],
      home: root.path,
      resultLimit: 1
    )
    XCTAssertEqual(matches.count, 1)
    XCTAssertTrue(resolvedPath(matches[0]).hasPrefix(resolvedPath(documents.path)))
  }

  func testDoesNotWalkOutsideFallbackRoots() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let document = root.appendingPathComponent("Private/ember-private.pdf")
    try FileManager.default.createDirectory(
      at: document.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try Data().write(to: document)
    defer { try? FileManager.default.removeItem(at: root) }

    setenv("PHOTON_FILE_SEARCH_STANDARD_ROOTS", "0", 1)
    defer { unsetenv("PHOTON_FILE_SEARCH_STANDARD_ROOTS") }

    let matches = FileSystemFallbackSearch.paths(
      matching: "ember",
      roots: FileSearchFallbackRoots.roots(for: FileSearchSettings(scope: .home), home: root.path),
      home: root.path,
      resultLimit: 20
    )

    XCTAssertTrue(matches.isEmpty)
  }

  func testFindsRyanLikeCapstonePathUnderDocumentsGrant() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let document = root
      .appendingPathComponent("Documents/School/Capstone/Individual Pitch", isDirectory: true)
      .appendingPathComponent("Ember_Individual_Pitch.pdf")
    try FileManager.default.createDirectory(
      at: document.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try Data("pitch".utf8).write(to: document)
    defer { try? FileManager.default.removeItem(at: root) }

    let roots = FileSearchFallbackRoots.roots(
      for: FileSearchSettings(scope: .home, grantedFolders: []),
      home: root.path
    )
    let matches = FileSystemFallbackSearch.paths(
      matching: "ember",
      roots: roots,
      home: root.path,
      resultLimit: 20
    )
    XCTAssertEqual(matches.map(resolvedPath), [resolvedPath(document.path)])
  }

  private func resolvedPath(_ path: String) -> String {
    URL(fileURLWithPath: path).resolvingSymlinksInPath().path
  }
}
