import XCTest
@testable import PhotonFiles

final class FileSearchFallbackRootsTests: XCTestCase {
  func testIncludesGrantedFoldersAndStandardHomeFolders() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let documents = root.appendingPathComponent("Documents", isDirectory: true)
    let desktop = root.appendingPathComponent("Desktop", isDirectory: true)
    try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: desktop, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let settings = FileSearchSettings(
      scope: .home,
      grantedFolders: [documents.path]
    )
    let roots = FileSearchFallbackRoots.roots(for: settings, home: root.path)
    XCTAssertTrue(roots.contains(documents.path))
    XCTAssertTrue(roots.contains(desktop.path))
  }

  func testStandardRootsCanBeDisabledForTests() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
      at: root.appendingPathComponent("Documents", isDirectory: true),
      withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: root) }

    setenv("PHOTON_FILE_SEARCH_STANDARD_ROOTS", "0", 1)
    defer { unsetenv("PHOTON_FILE_SEARCH_STANDARD_ROOTS") }

    let roots = FileSearchFallbackRoots.roots(for: FileSearchSettings(scope: .home), home: root.path)
    XCTAssertTrue(roots.isEmpty)
  }
}
