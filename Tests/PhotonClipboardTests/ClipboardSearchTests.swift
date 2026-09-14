import Foundation
import PhotonClipboard
import XCTest

final class ClipboardSearchTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)

  private func text(
    _ value: String,
    minutesAgo: Double = 0,
    pinned: Bool = false,
    app: String? = nil
  ) -> ClipboardItem {
    var item = ClipboardItem.text(value, at: now.addingTimeInterval(-minutesAgo * 60), isPinned: pinned)
    item.sourceAppName = app
    return item
  }

  private func image(minutesAgo: Double = 0) -> ClipboardItem {
    ClipboardItem(
      kind: .image,
      createdAt: now.addingTimeInterval(-minutesAgo * 60),
      hasImage: true,
      imageWidth: 800,
      imageHeight: 600,
      byteCount: 1000,
      contentHash: "i:\(minutesAgo)"
    )
  }

  private func file(_ paths: [String], minutesAgo: Double = 0) -> ClipboardItem {
    ClipboardItem(
      kind: .file,
      createdAt: now.addingTimeInterval(-minutesAgo * 60),
      filePaths: paths,
      contentHash: ClipboardContent.hash(filePaths: paths)
    )
  }

  private func titles(_ items: [ClipboardItem], _ query: String) -> [String] {
    ClipboardSearch.rank(items, query: query, now: now).map(\.title)
  }

  // MARK: Empty query

  func testEmptyQueryListsPinnedFirstThenNewest() {
    let items = [
      text("newest"),
      text("older pinned", minutesAgo: 30, pinned: true),
      text("middle", minutesAgo: 10),
      text("oldest pinned", minutesAgo: 60, pinned: true)
    ]
    XCTAssertEqual(titles(items, ""), ["older pinned", "oldest pinned", "newest", "middle"])
    XCTAssertEqual(titles(items, "   "), ["older pinned", "oldest pinned", "newest", "middle"])
  }

  // MARK: Matching

  func testNonMatchingItemsAreExcluded() {
    let items = [text("swift package manager"), text("grocery list"), image()]
    XCTAssertEqual(titles(items, "swift"), ["swift package manager"])
    XCTAssertTrue(titles(items, "zzzz").isEmpty)
  }

  func testMatchingIsCaseInsensitive() {
    let items = [text("Hello World")]
    XCTAssertEqual(titles(items, "hello"), ["Hello World"])
    XCTAssertEqual(titles(items, "WORLD"), ["Hello World"])
  }

  func testTitleMatchOutranksBodyMatch() {
    let inTitle = text("deploy notes", minutesAgo: 30)
    let inBody = text("todo\nremember to deploy tomorrow", minutesAgo: 1)
    XCTAssertEqual(titles([inBody, inTitle], "deploy"), ["deploy notes", "todo"])
  }

  func testPrefixMatchOutranksLaterOccurrence() {
    let prefix = text("photon launcher", minutesAgo: 30)
    let later = text("the photon project", minutesAgo: 1)
    XCTAssertEqual(titles([later, prefix], "photon"), ["photon launcher", "the photon project"])
  }

  func testExactSubstringOutranksFuzzySubsequence() {
    let exact = text("config file", minutesAgo: 30)
    let fuzzy = text("c o n f i g", minutesAgo: 1)
    XCTAssertEqual(titles([fuzzy, exact], "config").first, "config file")
  }

  func testAllTokensMustMatch() {
    let both = text("red apple pie")
    let one = text("red bicycle")
    XCTAssertEqual(titles([one, both], "red apple"), ["red apple pie"])
  }

  func testSearchesFilePaths() {
    let items = [file(["/Users/ryan/Documents/report-final.pdf"]), text("unrelated")]
    XCTAssertEqual(titles(items, "report"), ["report-final.pdf"])
    XCTAssertEqual(titles(items, "documents"), ["report-final.pdf"])
  }

  func testSearchesLinkHosts() {
    let items = [text("https://github.com/RyanStoffel/photon"), text("plain text")]
    XCTAssertEqual(titles(items, "github"), ["https://github.com/RyanStoffel/photon"])
  }

  func testSearchesSourceAppName() {
    let items = [text("meeting notes", app: "Notes"), text("terminal output", app: "Terminal")]
    XCTAssertEqual(titles(items, "terminal"), ["terminal output"])
    XCTAssertEqual(titles(items, "notes").first, "meeting notes")
  }

  func testKindKeywordFindsImages() {
    let items = [image(), text("image of a cat", minutesAgo: 1)]
    let result = titles(items, "image")
    XCTAssertEqual(result.count, 2)
    XCTAssertEqual(result.first, "Image", "an exact title match outranks a prefix match")
    XCTAssertEqual(titles([image(), text("some text")], "ima"), ["Image"], "kind keywords match on prefix")
  }

  // MARK: Tie breakers

  func testRecentItemsWinTiesAmongEqualMatches() {
    let older = text("release checklist", minutesAgo: 120)
    let newer = text("release checklist v2", minutesAgo: 1)
    XCTAssertEqual(titles([older, newer], "release").first, "release checklist v2")
  }

  func testPinnedBoostBreaksTies() {
    let loose = text("api token", minutesAgo: 1)
    let pinned = text("api token backup", minutesAgo: 1, pinned: true)
    XCTAssertEqual(titles([loose, pinned], "api").first, "api token backup")
  }

  func testMatchesExposeScoresInDescendingOrder() {
    let items = [text("photon"), text("the photon"), text("photon in body\nphoton")]
    let matches = ClipboardSearch.matches(items, query: "photon", now: now)
    XCTAssertEqual(matches.count, 3)
    XCTAssertEqual(matches, matches.sorted { $0.score > $1.score })
  }

  // MARK: Content helpers

  func testLinkDetection() {
    XCTAssertTrue(ClipboardContent.isLink("https://example.com/path?q=1"))
    XCTAssertTrue(ClipboardContent.isLink("  http://example.com  "))
    XCTAssertFalse(ClipboardContent.isLink("https://example.com and more"))
    XCTAssertFalse(ClipboardContent.isLink("example.com"))
    XCTAssertFalse(ClipboardContent.isLink("mailto:someone@example.com"))
    XCTAssertEqual(ClipboardItem.text("https://example.com").kind, .link)
    XCTAssertEqual(ClipboardItem.text("hello").kind, .text)
  }

  func testTitleUsesFirstNonBlankLineAndCollapsesWhitespace() {
    XCTAssertEqual(ClipboardItem.text("\n\n  first   line \nsecond").title, "first line")
    let long = String(repeating: "x", count: 200)
    XCTAssertEqual(ClipboardItem.text(long).title.count, 121)
    XCTAssertTrue(ClipboardItem.text(long).title.hasSuffix("…"))
  }

  func testLargeTextIsTruncatedInline() {
    let large = String(repeating: "a", count: ClipboardItem.inlineTextLimit + 10)
    let item = ClipboardItem.text(large)
    XCTAssertTrue(item.isTextTruncated)
    XCTAssertEqual(item.text?.count, ClipboardItem.inlineTextLimit)
    XCTAssertEqual(item.byteCount, large.utf8.count)
  }

  func testLauncherPrefixParsing() {
    XCTAssertEqual(ClipboardProvider.historyQuery(fromLauncherQuery: "cb foo"), "foo")
    XCTAssertEqual(ClipboardProvider.historyQuery(fromLauncherQuery: "CB  foo bar"), "foo bar")
    XCTAssertEqual(ClipboardProvider.historyQuery(fromLauncherQuery: "clipboard "), "")
    XCTAssertNil(ClipboardProvider.historyQuery(fromLauncherQuery: "cb"))
    XCTAssertNil(ClipboardProvider.historyQuery(fromLauncherQuery: "cbx foo"))
    XCTAssertNil(ClipboardProvider.historyQuery(fromLauncherQuery: "safari"))
  }
}
