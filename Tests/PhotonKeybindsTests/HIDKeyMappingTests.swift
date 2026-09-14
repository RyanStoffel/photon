import PhotonKeybinds
import XCTest

final class HIDKeyMappingTests: XCTestCase {
  private let capsLockToF18 = HIDKeyMappingPair(source: 0x7_0000_0039, destination: 0x7_0000_006d)
  private let sectionToGrave = HIDKeyMappingPair(source: 0x7_0000_0064, destination: 0x7_0000_0035)

  func testParsesHidutilDescriptionOutput() {
    let output = """
    (
            {
            HIDKeyboardModifierMappingDst = 30064771181;
            HIDKeyboardModifierMappingSrc = 30064771129;
        },
            {
            HIDKeyboardModifierMappingDst = 30064771125;
            HIDKeyboardModifierMappingSrc = 30064771172;
        }
    )
    """
    XCTAssertEqual(HIDKeyMapping.parse(hidutilOutput: output), [capsLockToF18, sectionToGrave])
  }

  func testParsesJSONAndHexForms() {
    let json = """
    [{"HIDKeyboardModifierMappingSrc":0x700000039,"HIDKeyboardModifierMappingDst":0x70000006D}]
    """
    XCTAssertEqual(HIDKeyMapping.parse(hidutilOutput: json), [capsLockToF18])
    XCTAssertEqual(HIDKeyMapping.parse(hidutilOutput: "(null)"), [])
    XCTAssertEqual(HIDKeyMapping.parse(hidutilOutput: ""), [])
    XCTAssertEqual(HIDKeyMapping.parse(hidutilOutput: "{ HIDKeyboardModifierMappingSrc = 1; }"), [])
  }

  func testPropertyArgumentIsValidJSONHidutilAccepts() throws {
    let argument = HIDKeyMapping.propertyArgument(for: [capsLockToF18])
    let expected = "{\"UserKeyMapping\":[{\"HIDKeyboardModifierMappingSrc\":30064771129,"
      + "\"HIDKeyboardModifierMappingDst\":30064771181}]}"
    XCTAssertEqual(argument, expected)
    let object = try JSONSerialization.jsonObject(with: Data(argument.utf8)) as? [String: [[String: UInt64]]]
    XCTAssertEqual(object?["UserKeyMapping"]?.first?["HIDKeyboardModifierMappingSrc"], capsLockToF18.source)
    XCTAssertEqual(HIDKeyMapping.propertyArgument(for: []), "{\"UserKeyMapping\":[]}")
  }

  func testArgumentAndParseRoundTrip() {
    let pairs = [capsLockToF18, sectionToGrave]
    XCTAssertEqual(HIDKeyMapping.parse(hidutilOutput: HIDKeyMapping.propertyArgument(for: pairs)), pairs)
  }

  func testMergingReplacesTheSameSourceAndKeepsOthers() {
    let rightCommandToF18 = HIDKeyMappingPair(source: 0x7_0000_00e7, destination: 0x7_0000_006d)
    let merged = HIDKeyMapping.merging([sectionToGrave, capsLockToF18], with: rightCommandToF18)
    XCTAssertEqual(merged, [sectionToGrave, capsLockToF18, rightCommandToF18])

    let replaced = HIDKeyMapping.merging(
      [capsLockToF18],
      with: HIDKeyMappingPair(source: capsLockToF18.source, destination: 0x7_0000_0029)
    )
    XCTAssertEqual(replaced, [HIDKeyMappingPair(source: capsLockToF18.source, destination: 0x7_0000_0029)])
  }

  func testRemovingOnlyTouchesOwnedMappings() {
    let foreignCapsLock = HIDKeyMappingPair(source: 0x7_0000_0039, destination: 0x7_0000_0029)
    let cleaned = HIDKeyMapping.removing(
      sources: [0x7_0000_0039, 0x7_0000_00e7],
      destination: 0x7_0000_006d,
      from: [capsLockToF18, sectionToGrave, foreignCapsLock]
    )
    XCTAssertEqual(cleaned, [sectionToGrave, foreignCapsLock])
  }
}
