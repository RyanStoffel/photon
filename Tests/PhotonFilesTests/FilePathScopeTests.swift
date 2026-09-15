import XCTest
@testable import PhotonFiles

final class FilePathScopeTests: XCTestCase {
  private let home = "/Users/ryan"

  func testHomeScopeAllowsDocumentsPDF() {
    let path = "/Users/ryan/Documents/School/Ember_Individual_Pitch.pdf"
    XCTAssertTrue(FilePathScope.isAllowed(path, scope: .home, home: home, extraFolders: []))
    XCTAssertFalse(FilePathScope.isBlockedSystemPath(path, home: home))
  }

  func testSystemPathIsBlockedForHomeScope() {
    let path = "/System/Library/CoreServices/Finder.app/Contents/Info.plist"
    XCTAssertTrue(FilePathScope.isBlockedSystemPath(path, home: home))
    let ranked = FileRanker.rank(
      [
        FileResult(
          path: path,
          displayName: "Info.plist",
          fileName: "Info.plist",
          kind: "Document",
          isFolder: false,
          isApplication: false,
          modified: nil,
          lastUsed: nil
        )
      ],
      query: "info",
      limit: 10,
      home: home,
      scope: .home
    )
    XCTAssertTrue(ranked.isEmpty)
  }

  func testEmberIndividualPitchSurvivesHomeScopeFilter() {
    let pitch = FileResult(
      path: "/Users/ryan/Documents/School/Capstone/Individual Pitch/Ember_Individual_Pitch.pdf",
      displayName: "Ember_Individual_Pitch.pdf",
      fileName: "Ember_Individual_Pitch.pdf",
      kind: "Document",
      isFolder: false,
      isApplication: false,
      modified: nil,
      lastUsed: nil
    )
    let ranked = FileRanker.rank([pitch], query: "ember_individual", limit: 10, home: home, scope: .home)
    XCTAssertEqual(ranked.count, 1)
    XCTAssertGreaterThanOrEqual(ranked[0].relevance, FileRanker.strongMatchThreshold)
  }

  func testFirmlinkHomePathIsAllowedAndNotBlocked() {
    let path = "/System/Volumes/Data/Users/ryan/Documents/School/Ember_Individual_Pitch.pdf"
    XCTAssertTrue(FilePathScope.isAllowed(path, scope: .home, home: home, extraFolders: []))
    XCTAssertFalse(FilePathScope.isBlockedSystemPath(path, home: home))
    let ranked = FileRanker.rank(
      [
        FileResult(
          path: path,
          displayName: "Ember_Individual_Pitch.pdf",
          fileName: "Ember_Individual_Pitch.pdf",
          kind: "Document",
          isFolder: false,
          isApplication: false,
          modified: nil,
          lastUsed: nil
        )
      ],
      query: "ember_individual",
      limit: 10,
      home: home,
      scope: .home
    )
    XCTAssertEqual(ranked.count, 1)
  }
}
