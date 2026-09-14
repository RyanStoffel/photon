import Foundation
import PhotonKeybinds
import XCTest

final class KeybindsConfigurationTests: XCTestCase {
  private let hyperLeft = KeyShortcut(keyCode: 123, modifiers: .hyper)
  private let commandSpace = KeyShortcut(keyCode: 49, modifiers: .command)

  func testDefaultsHaveOneBindingPerActionAndNoConflicts() {
    let configuration = KeybindsConfiguration.default
    XCTAssertEqual(configuration.windowBindings.map(\.action), WindowAction.allCases)
    XCTAssertTrue(configuration.hyperKey.enabled)
    XCTAssertEqual(configuration.hyperKey.source, .capsLock)
    XCTAssertEqual(configuration.hyperKey.tapBehavior, .nothing)
    XCTAssertTrue(configuration.appHotkeys.isEmpty)
    XCTAssertTrue(configuration.conflicts(launcher: commandSpace).isEmpty)
    XCTAssertEqual(configuration.shortcut(for: .leftHalf), hyperLeft)
  }

  func testDetectsConflictsBetweenAppsWindowsAndLauncher() {
    var configuration = KeybindsConfiguration.default
    let safari = AppHotkey(bundleIdentifier: "com.apple.Safari", name: "Safari", shortcut: hyperLeft)
    let mail = AppHotkey(bundleIdentifier: "com.apple.mail", name: "Mail", shortcut: commandSpace)
    let notes = AppHotkey(bundleIdentifier: "com.apple.Notes", name: "Notes", shortcut: nil)
    configuration.appHotkeys = [safari, mail, notes]

    let conflicts = configuration.conflicts(launcher: commandSpace)
    XCTAssertEqual(conflicts.count, 2)
    XCTAssertEqual(conflicts[0].shortcut, commandSpace)
    XCTAssertEqual(conflicts[0].owners, [.launcher, .app(mail.id)])
    XCTAssertEqual(conflicts[1].shortcut, hyperLeft)
    XCTAssertEqual(conflicts[1].owners, [.app(safari.id), .window(.leftHalf)])

    let owners = configuration.conflictingOwners(launcher: commandSpace)
    XCTAssertEqual(owners, [.launcher, .app(mail.id), .app(safari.id), .window(.leftHalf)])
    XCTAssertFalse(owners.contains(.app(notes.id)))
    XCTAssertFalse(owners.contains(.window(.rightHalf)))
  }

  func testWindowShortcutsCanConflictWithEachOther() {
    var configuration = KeybindsConfiguration.default
    configuration.setShortcut(hyperLeft, for: .rightHalf)
    let conflicts = configuration.conflicts()
    XCTAssertEqual(conflicts.count, 1)
    XCTAssertEqual(conflicts[0].owners, [.window(.leftHalf), .window(.rightHalf)])
    XCTAssertEqual(configuration.conflicts(launcher: commandSpace).count, 1)
  }

  func testSetAndResetWindowShortcuts() {
    var configuration = KeybindsConfiguration.default
    configuration.setShortcut(nil, for: .maximize)
    XCTAssertNil(configuration.shortcut(for: .maximize))
    configuration.setShortcut(commandSpace, for: .restore)
    XCTAssertEqual(configuration.shortcut(for: .restore), commandSpace)
    configuration.resetWindowBindings()
    XCTAssertEqual(configuration, .default)
  }

  func testNormalizedFillsMissingActionsAndDropsDuplicates() {
    let partial = KeybindsConfiguration(
      windowBindings: [
        WindowBinding(action: .center, shortcut: nil),
        WindowBinding(action: .center, shortcut: commandSpace),
        WindowBinding(action: .maximize, shortcut: commandSpace)
      ]
    )
    let normalized = partial.normalized()
    XCTAssertEqual(normalized.windowBindings.map(\.action), WindowAction.allCases)
    XCTAssertNil(normalized.shortcut(for: .center))
    XCTAssertEqual(normalized.shortcut(for: .maximize), commandSpace)
    XCTAssertEqual(normalized.shortcut(for: .leftHalf), hyperLeft)
  }

  func testCodableRoundTripKeepsEverything() throws {
    var configuration = KeybindsConfiguration.default
    configuration.hyperKey = HyperKeySettings(enabled: false, source: .rightCommand, tapBehavior: .escape)
    configuration.appHotkeys = [
      AppHotkey(bundleIdentifier: "com.apple.Safari", name: "Safari", shortcut: commandSpace),
      AppHotkey(bundleIdentifier: "com.apple.Terminal", name: "Terminal", shortcut: nil)
    ]
    configuration.setShortcut(nil, for: .center)

    let data = try JSONEncoder().encode(configuration)
    let decoded = try JSONDecoder().decode(KeybindsConfiguration.self, from: data)
    XCTAssertEqual(decoded, configuration)
  }

  func testDecodesPartialJSONWithDefaults() throws {
    let json = """
    {"hyperKey": {"source": "section"}, "windowBindings": [{"action": "leftHalf"}]}
    """
    let decoded = try JSONDecoder().decode(KeybindsConfiguration.self, from: Data(json.utf8))
    XCTAssertTrue(decoded.hyperKey.enabled)
    XCTAssertEqual(decoded.hyperKey.source, .section)
    XCTAssertEqual(decoded.hyperKey.tapBehavior, .nothing)
    XCTAssertTrue(decoded.appHotkeys.isEmpty)
    XCTAssertNil(decoded.shortcut(for: .leftHalf))
    XCTAssertEqual(decoded.shortcut(for: .rightHalf), WindowAction.rightHalf.defaultShortcut)
    XCTAssertEqual(decoded.windowBindings.count, WindowAction.allCases.count)

    let empty = try JSONDecoder().decode(KeybindsConfiguration.self, from: Data("{}".utf8))
    XCTAssertEqual(empty, .default)
  }

  func testHyperKeySourcesMapToHIDUsages() {
    XCTAssertEqual(HyperKeySource.capsLock.hidUsage, 0x7_0000_0039)
    XCTAssertEqual(HyperKeySource.rightCommand.hidUsage, 0x7_0000_00e7)
    XCTAssertNil(HyperKeySource.f18.hidUsage)
    XCTAssertEqual(HyperKeySource.destinationUsage, 0x7_0000_006d)
    XCTAssertEqual(HyperKeySource.destinationKeyCode, 79)
    XCTAssertEqual(KeyNames.name(for: HyperKeySource.destinationKeyCode), "F18")
  }
}
