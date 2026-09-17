import XCTest
@testable import PhotonFiles

final class FileSearchFallbackRootsTests: XCTestCase {
  func testIncludesGrantedFoldersOnly() throws {
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
    XCTAssertEqual(roots, [documents.path])
    XCTAssertFalse(roots.contains(desktop.path))
  }

  func testDoesNotProbeStandardHomeFoldersWithoutAGrant() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
      at: root.appendingPathComponent("Documents", isDirectory: true),
      withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: root) }

    let roots = FileSearchFallbackRoots.roots(for: FileSearchSettings(scope: .home), home: root.path)
    XCTAssertTrue(roots.isEmpty)
  }

  func testSuggestedGrantFoldersAreStandardUserDirectories() {
    let home = "/Users/ryan"
    let suggested = FileSearchFallbackRoots.suggestedGrantFolders(home: home).map(\.lastPathComponent)
    XCTAssertEqual(suggested, ["Documents", "Desktop", "Downloads"])
  }
}
