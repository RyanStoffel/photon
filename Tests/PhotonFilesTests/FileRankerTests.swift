import XCTest
@testable import PhotonFiles

final class FileRankerTests: XCTestCase {
  private let home = "/Users/ryan"

  private func file(
    _ path: String,
    displayName: String? = nil,
    isFolder: Bool = false,
    isApplication: Bool = false,
    lastUsed: Date? = nil,
    modified: Date? = nil
  ) -> FileResult {
    let name = (path as NSString).lastPathComponent
    return FileResult(
      path: path,
      displayName: displayName ?? name,
      fileName: name,
      kind: isFolder ? "Folder" : "Document",
      isFolder: isFolder,
      isApplication: isApplication,
      modified: modified,
      lastUsed: lastUsed
    )
  }

  func testExactNameOutranksPrefixWordAndSubstring() {
    let exact = file("/a/Budget.numbers")
    let prefix = file("/a/Budget 2026.numbers")
    let word = file("/a/Annual Budget.numbers")
    let substring = file("/a/Rebudgeting.numbers")
    let ranked = FileRanker.rank([substring, word, prefix, exact], query: "budget", limit: 10)
    XCTAssertEqual(ranked.map(\.file.path), [exact.path, prefix.path, word.path, substring.path])
    XCTAssertEqual(ranked[0].relevance, 1)
    XCTAssertGreaterThanOrEqual(ranked[2].relevance, FileRanker.strongMatchThreshold)
    XCTAssertLessThan(ranked[3].relevance, FileRanker.strongMatchThreshold)
  }

  func testMatchingIsCaseAndDiacriticInsensitive() {
    let accented = file("/a/Résumé.pdf")
    XCTAssertEqual(FileRanker.relevance(of: accented, query: "RESUME"), 1)
  }

  func testCamelCaseHumpsCountAsWordStarts() {
    let camel = file("/a/PhotonLauncher.swift")
    XCTAssertEqual(FileRanker.relevance(of: camel, query: "launcher"), 0.7)
  }

  func testExtensionOnlyMatchScoresBelowNameMatch() {
    let name = file("/a/md-guide.txt")
    let extensionOnly = file("/a/Notes.md")
    let unrelated = file("/a/Readme.txt")
    let ranked = FileRanker.rank([unrelated, extensionOnly, name], query: "md", limit: 10)
    XCTAssertEqual(ranked.map(\.file.path), [name.path, extensionOnly.path])
    XCTAssertGreaterThan(ranked[0].relevance, ranked[1].relevance)
  }

  func testMultiTermQueryAveragesTermScores() {
    let both = file("/a/Annual Report.pdf")
    let one = file("/a/Report Draft.pdf")
    let bothScore = FileRanker.relevance(of: both, query: "annual report")
    let oneScore = FileRanker.relevance(of: one, query: "annual report")
    XCTAssertEqual(bothScore, 1)
    XCTAssertGreaterThan(bothScore, oneScore)
  }

  func testLastUsedBreaksTiesAndMissingDatesSortLast() {
    let now = Date()
    let recent = file("/a/x/Plan.md", lastUsed: now)
    let older = file("/a/y/Plan.md", lastUsed: now.addingTimeInterval(-3600))
    let never = file("/a/z/Plan.md")
    let ranked = FileRanker.rank([never, older, recent], query: "plan", limit: 10)
    XCTAssertEqual(ranked.map(\.file.path), [recent.path, older.path, never.path])
  }

  func testModifiedDateThenNameBreakRemainingTies() {
    let now = Date()
    let touched = file("/a/Beta/Item.txt", displayName: "Item.txt", modified: now)
    let stale = file("/a/Alpha/Item.txt", displayName: "Item.txt", modified: now.addingTimeInterval(-60))
    let undated = file("/a/Gamma/Item.txt", displayName: "Item.txt")
    let ranked = FileRanker.rank([undated, stale, touched], query: "item", limit: 10)
    XCTAssertEqual(ranked.map(\.file.path), [touched.path, stale.path, undated.path])
  }

  func testLimitCapsResults() {
    let files = (0 ..< 20).map { file("/a/Item \($0).txt") }
    XCTAssertEqual(FileRanker.rank(files, query: "item", limit: 5).count, 5)
    XCTAssertTrue(FileRanker.rank(files, query: "item", limit: 0).isEmpty)
  }

  func testDuplicatePathsCollapse() {
    let a = file("/a/Same.txt")
    XCTAssertEqual(FileRanker.rank([a, a], query: "same", limit: 10).count, 1)
  }

  func testExcludedFoldersAreDropped() {
    let inside = file("/Users/ryan/Private/Secret.txt")
    let lookalike = file("/Users/ryan/PrivateStuff/Secret.txt")
    let elsewhere = file("/Users/ryan/Documents/Secret.txt")
    let ranked = FileRanker.rank(
      [inside, lookalike, elsewhere],
      query: "secret",
      excludedFolders: ["~/Private/"],
      limit: 10,
      home: home
    )
    XCTAssertEqual(ranked.map(\.file.path), [elsewhere.path, lookalike.path])
  }

  func testIsExcludedMatchesWholeComponentsOnly() {
    XCTAssertTrue(FileRanker.isExcluded("/Volumes/Backup/a.txt", folders: ["/Volumes/Backup"], home: home))
    XCTAssertTrue(FileRanker.isExcluded("/Volumes/Backup", folders: ["/Volumes/Backup"], home: home))
    XCTAssertFalse(FileRanker.isExcluded("/Volumes/Backup2/a.txt", folders: ["/Volumes/Backup"], home: home))
    XCTAssertTrue(FileRanker.isExcluded("/Users/ryan/Library/x", folders: ["~/Library"], home: home))
    XCTAssertFalse(FileRanker.isExcluded("/Users/ryan/Library/x", folders: [" ", ""], home: home))
  }

  func testApplicationsCanBeFilteredOut() {
    let app = file("/Applications/Notes.app", isApplication: true)
    let doc = file("/a/Notes.txt")
    let inline = FileRanker.rank([app, doc], query: "notes", includeApplications: false, limit: 10)
    XCTAssertEqual(inline.map(\.file.path), [doc.path])
    let full = FileRanker.rank([app, doc], query: "notes", limit: 10)
    XCTAssertEqual(full.count, 2)
  }

  func testFoldersRankLikeFiles() {
    let folder = file("/Users/ryan/Projects", isFolder: true)
    let document = file("/Users/ryan/Projects.txt")
    let ranked = FileRanker.rank([document, folder], query: "projects", limit: 10)
    XCTAssertEqual(ranked.count, 2)
    XCTAssertEqual(ranked[0].relevance, 1)
    XCTAssertEqual(ranked[1].relevance, 1)
  }

  func testUnderscoreQueryMatchesPitchPDF() {
    let pitch = file(
      "/Users/ryan/Documents/School/Capstone/Individual Pitch/Ember_Individual_Pitch.pdf",
      displayName: "Ember_Individual_Pitch.pdf"
    )
    let ranked = FileRanker.rank([pitch], query: "ember_individual", limit: 10, home: home)
    XCTAssertEqual(ranked.count, 1)
    XCTAssertGreaterThanOrEqual(ranked[0].relevance, FileRanker.strongMatchThreshold)
  }

  func testEmberQuerySurfacesPitchPDFAbovePrefixedFolders() {
    let exactFolder = file("/Users/ryan/Developer/school/capstone/ember", isFolder: true)
    let poc = file("/Users/ryan/Developer/school/capstone/ember_poc", isFolder: true)
    let pdf = file(
      "/Users/ryan/Documents/School/Capstone/Individual Pitch/Ember_Individual_Pitch.pdf",
      displayName: "Ember_Individual_Pitch.pdf"
    )
    let ranked = FileRanker.rank([poc, pdf, exactFolder], query: "ember", limit: 10, home: home)
    XCTAssertEqual(
      ranked.map(\.file.path),
      [exactFolder.path, pdf.path, poc.path]
    )
    XCTAssertGreaterThanOrEqual(ranked[1].relevance, 0.93)
  }

  func testRelativePathMatchRanksBelowExactStem() {
    let exact = file("/Users/ryan/Downloads/ember_individual.txt")
    let byPath = file(
      "/Users/ryan/Documents/School/Capstone/Individual Pitch/Ember_Individual_Pitch.pdf",
      displayName: "Ember_Individual_Pitch.pdf"
    )
    let ranked = FileRanker.rank([byPath, exact], query: "ember_individual", limit: 10, home: home)
    XCTAssertEqual(ranked.first?.file.path, exact.path)
    XCTAssertGreaterThan(ranked[0].relevance, ranked[1].relevance)
  }

  func testWeakSpotlightHitsWithoutFuzzyMatchAreDropped() {
    let unrelated = file("/Users/ryan/Library/Caches/com.apple.something/random.txt")
    XCTAssertTrue(FileRanker.rank([unrelated], query: "ember_individual", limit: 10, home: home).isEmpty)
  }
}
