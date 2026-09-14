import Foundation
import PhotonNotes
import XCTest

final class MarkdownStylerTests: XCTestCase {
  private func spans(_ text: String, _ kind: MarkdownSpanKind) -> [String] {
    let nsText = text as NSString
    return MarkdownStyler.spans(in: text)
      .filter { $0.kind == kind }
      .map { nsText.substring(with: $0.range) }
  }

  func testHeadingSplitsMarkerAndContent() {
    let text = "## Plan\nbody"
    XCTAssertEqual(spans(text, .headingMarker(level: 2)), ["## "])
    XCTAssertEqual(spans(text, .heading(level: 2)), ["Plan"])
    XCTAssertTrue(spans(text, .heading(level: 1)).isEmpty)
  }

  func testHashWithoutSpaceIsNotAHeading() {
    XCTAssertTrue(spans("#hashtag", .headingMarker(level: 1)).isEmpty)
    XCTAssertEqual(spans("#", .headingMarker(level: 1)), ["#"])
  }

  func testBoldItalicAndBoldItalic() {
    let text = "a **bold** b *it* c ***both*** d __under__ e _score_"
    XCTAssertEqual(spans(text, .bold), ["bold", "under"])
    XCTAssertEqual(spans(text, .italic), ["it", "score"])
    XCTAssertEqual(spans(text, .boldItalic), ["both"])
    XCTAssertEqual(spans(text, .syntax), ["**", "**", "*", "*", "***", "***", "__", "__", "_", "_"])
  }

  func testUnderscoresInsideWordsAreNotItalic() {
    XCTAssertTrue(spans("use snake_case_names here", .italic).isEmpty)
    XCTAssertTrue(spans("2 * 3 * 4", .italic).isEmpty)
  }

  func testInlineCodeWinsOverEmphasis() {
    let text = "run `a * b * c` now"
    XCTAssertEqual(spans(text, .inlineCode), ["a * b * c"])
    XCTAssertTrue(spans(text, .italic).isEmpty)
    XCTAssertEqual(spans("x ``a`b`` y", .inlineCode), ["a`b"])
  }

  func testBulletAndNumberedListMarkers() {
    XCTAssertEqual(spans("- one\n* two\n+ three\n1. four\n12) five", .listMarker), ["- ", "* ", "+ ", "1. ", "12) "])
    XCTAssertEqual(spans("  - nested", .listMarker), ["  - "])
    XCTAssertTrue(spans("-no space", .listMarker).isEmpty)
  }

  func testCheckboxesAndCompletedItems() {
    let text = "- [ ] open\n- [x] done\n- [X] shouting"
    XCTAssertEqual(spans(text, .checkbox(checked: false)), ["[ ]"])
    XCTAssertEqual(spans(text, .checkbox(checked: true)), ["[x]", "[X]"])
    XCTAssertEqual(spans(text, .completedItem), ["done", "shouting"])
  }

  func testFencedCodeBlocks() {
    let text = "before\n```swift\nlet x = **not bold**\n```\n*after*"
    XCTAssertEqual(spans(text, .codeFence), ["```swift", "```"])
    XCTAssertEqual(spans(text, .codeBlock), ["let x = **not bold**"])
    XCTAssertTrue(spans(text, .bold).isEmpty)
    XCTAssertEqual(spans(text, .italic), ["after"])
    XCTAssertTrue(MarkdownStyler.requiresFullPass(text))
    XCTAssertFalse(MarkdownStyler.requiresFullPass("plain"))
  }

  func testPartialRangeOnlyStylesIntersectingLines() {
    let text = "# One\n**two**\n# Three"
    let nsText = text as NSString
    let second = nsText.range(of: "**two**")
    let partial = MarkdownStyler.spans(in: text, range: second)
    XCTAssertEqual(partial.filter { $0.kind == .bold }.count, 1)
    XCTAssertTrue(partial.allSatisfy { NSIntersectionRange($0.range, second).length > 0 })
  }

  func testRangesAreUTF16Offsets() {
    let text = "😀 **bold**"
    let nsText = text as NSString
    let bold = MarkdownStyler.spans(in: text).first { $0.kind == .bold }
    XCTAssertEqual(bold.map { nsText.substring(with: $0.range) }, "bold")
    XCTAssertEqual(bold?.range.location, 5)
  }

  func testEmptyTextHasNoSpans() {
    XCTAssertTrue(MarkdownStyler.spans(in: "").isEmpty)
  }

  func testCheckboxToggleOnAndAroundBrackets() {
    let text = "- [ ] task"
    let toggle = MarkdownCheckbox.toggle(in: text, at: 3)
    XCTAssertEqual(toggle?.range, NSRange(location: 2, length: 3))
    XCTAssertEqual(toggle?.replacement, "[x]")
    XCTAssertEqual(MarkdownCheckbox.toggle(in: text, at: 5)?.replacement, "[x]")
    XCTAssertNil(MarkdownCheckbox.toggle(in: text, at: 8))
    XCTAssertEqual(MarkdownCheckbox.toggle(in: "- [x] done", at: 2)?.replacement, "[ ]")
    XCTAssertNil(MarkdownCheckbox.toggle(in: "plain", at: 2))
    XCTAssertNil(MarkdownCheckbox.toggle(in: text, at: 99))
  }

  func testListContinuation() {
    XCTAssertEqual(MarkdownList.continuation(at: 6, in: "- item"), .insert("\n- "))
    XCTAssertEqual(MarkdownList.continuation(at: 10, in: "- [x] done"), .insert("\n- [ ] "))
    XCTAssertEqual(MarkdownList.continuation(at: 7, in: "2. step"), .insert("\n3. "))
    XCTAssertEqual(MarkdownList.continuation(at: 9, in: "  9) deep"), .insert("\n  10) "))
    XCTAssertEqual(MarkdownList.continuation(at: 2, in: "- "), .terminate(NSRange(location: 0, length: 2)))
    XCTAssertEqual(MarkdownList.continuation(at: 6, in: "- [ ] "), .terminate(NSRange(location: 0, length: 6)))
    XCTAssertNil(MarkdownList.continuation(at: 3, in: "- item"))
    XCTAssertNil(MarkdownList.continuation(at: 5, in: "plain"))
    XCTAssertEqual(MarkdownList.continuation(at: 6, in: "- item\nnext"), .insert("\n- "))
  }
}
