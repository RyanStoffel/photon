import Foundation
import PhotonKeybinds
import XCTest

final class KeyShortcutTests: XCTestCase {
  func testParsesNamedModifiersAndKeys() {
    XCTAssertEqual(KeyShortcut.parse("hyper+left"), KeyShortcut(keyCode: 123, modifiers: .hyper))
    XCTAssertEqual(KeyShortcut.parse("cmd+shift+k"), KeyShortcut(keyCode: 40, modifiers: [.command, .shift]))
    XCTAssertEqual(KeyShortcut.parse("ctrl-alt-delete"), KeyShortcut(keyCode: 51, modifiers: [.control, .option]))
    XCTAssertEqual(
      KeyShortcut.parse("Control + Option + Return"),
      KeyShortcut(keyCode: 36, modifiers: [.control, .option])
    )
    XCTAssertEqual(KeyShortcut.parse("hyper+Page Up"), KeyShortcut(keyCode: 116, modifiers: .hyper))
    XCTAssertEqual(KeyShortcut.parse("cmd+-"), KeyShortcut(keyCode: 27, modifiers: .command))
    XCTAssertEqual(KeyShortcut.parse("hyper+]"), KeyShortcut(keyCode: 30, modifiers: .hyper))
  }

  func testParsesGlyphForms() {
    XCTAssertEqual(KeyShortcut.parse("⌃⌥⇧⌘Return"), KeyShortcut(keyCode: 36, modifiers: .hyper))
    XCTAssertEqual(KeyShortcut.parse("✦←"), KeyShortcut(keyCode: 123, modifiers: .hyper))
    XCTAssertEqual(KeyShortcut.parse("⌘⇧K"), KeyShortcut(keyCode: 40, modifiers: [.command, .shift]))
    XCTAssertEqual(KeyShortcut.parse("^a"), KeyShortcut(keyCode: 0, modifiers: .control))
    XCTAssertEqual(KeyShortcut.parse("⌘-"), KeyShortcut(keyCode: 27, modifiers: .command))
  }

  func testAllFourModifiersAreHyper() {
    let spelledOut = KeyShortcut.parse("ctrl+opt+shift+cmd+c")
    XCTAssertEqual(spelledOut, KeyShortcut.parse("hyper+c"))
    XCTAssertTrue(spelledOut?.isHyper ?? false)
    XCTAssertFalse(KeyShortcut.parse("ctrl+opt+shift+c")?.isHyper ?? true)
  }

  func testRejectsMalformedInput() {
    XCTAssertNil(KeyShortcut.parse(""))
    XCTAssertNil(KeyShortcut.parse("cmd+"))
    XCTAssertNil(KeyShortcut.parse("cmd+bogus"))
    XCTAssertNil(KeyShortcut.parse("cmd+a+b"))
    XCTAssertNil(KeyShortcut.parse("hyper"))
  }

  func testFormatsWithStandardGlyphOrder() {
    XCTAssertEqual(KeyShortcut(keyCode: 40, modifiers: [.shift, .command]).displayString, "⇧⌘K")
    XCTAssertEqual(KeyShortcut(keyCode: 36, modifiers: [.control, .option]).displayString, "⌃⌥Return")
    XCTAssertEqual(KeyShortcut(keyCode: 123, modifiers: .hyper).displayString, "✦←")
    XCTAssertEqual(KeyShortcut(keyCode: 49, modifiers: .command).displayString, "⌘Space")
    XCTAssertEqual(KeyShortcut(keyCode: 200, modifiers: .command).displayString, "⌘Key 200")
  }

  func testFormatAndParseRoundTrip() {
    let modifiers: [KeyModifiers] = [
      .command,
      [.command, .shift],
      [.control, .option],
      .hyper,
      [.control, .option, .shift]
    ]
    let keys: [UInt16] = [0, 8, 18, 24, 27, 30, 33, 36, 48, 49, 51, 53, 96, 115, 116, 117, 121, 122, 123, 124, 125, 126]
    for modifier in modifiers {
      for key in keys {
        let shortcut = KeyShortcut(keyCode: key, modifiers: modifier)
        XCTAssertEqual(KeyShortcut.parse(shortcut.displayString), shortcut, shortcut.displayString)
      }
    }
  }

  func testBindableRequiresModifiersUnlessFunctionKey() {
    XCTAssertTrue(KeyShortcut(keyCode: 0, modifiers: .command).isBindable)
    XCTAssertFalse(KeyShortcut(keyCode: 0, modifiers: []).isBindable)
    XCTAssertTrue(KeyShortcut(keyCode: 79, modifiers: []).isBindable)
  }

  func testCarbonAndCoreGraphicsConversionsRoundTrip() {
    let all: [KeyModifiers] = [[], .control, .option, .shift, .command, .hyper, [.control, .command]]
    for modifiers in all {
      XCTAssertEqual(KeyModifiers(carbonModifiers: modifiers.carbonModifiers), modifiers)
      XCTAssertEqual(KeyModifiers(cgEventFlags: modifiers.cgEventFlags), modifiers)
    }
    XCTAssertEqual(KeyModifiers.command.carbonModifiers, 0x0100)
    XCTAssertEqual(KeyModifiers.shift.carbonModifiers, 0x0200)
    XCTAssertEqual(KeyModifiers.option.carbonModifiers, 0x0800)
    XCTAssertEqual(KeyModifiers.control.carbonModifiers, 0x1000)
    XCTAssertEqual(KeyModifiers.hyper.cgEventFlags, 0x001e_0000)
    XCTAssertEqual(KeyModifiers(cgEventFlags: 0x0010_0100), .command)
  }

  func testCodableRoundTrip() throws {
    let shortcut = KeyShortcut(keyCode: 123, modifiers: .hyper)
    let data = try JSONEncoder().encode(shortcut)
    let object = try JSONSerialization.jsonObject(with: data) as? [String: Int]
    XCTAssertEqual(object, ["keyCode": 123, "modifiers": 15])
    XCTAssertEqual(try JSONDecoder().decode(KeyShortcut.self, from: data), shortcut)
  }
}
