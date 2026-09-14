import PhotonApps
import XCTest

final class SystemSettingsPaneMetadataTests: XCTestCase {
  func testLocalizedInfoPlistDisplayNameWinsOverStem() {
    let name = SystemSettingsPaneMetadata.displayName(
      info: ["CFBundleName": "DesktopScreenSaverPref"],
      localizedInfo: ["CFBundleName": "Wallpaper"],
      fallbackStem: "DesktopScreenSaverPref"
    )
    XCTAssertEqual(name, "Wallpaper")
  }

  func testCFBundleDisplayNamePreferredOverCFBundleName() {
    let name = SystemSettingsPaneMetadata.displayName(
      info: [
        "CFBundleDisplayName": "Privacy & Security",
        "CFBundleName": "SecurityPref",
      ],
      localizedInfo: nil,
      fallbackStem: "SecurityPref"
    )
    XCTAssertEqual(name, "Privacy & Security")
  }

  func testKnownStemMapsToHumanTitleWhenPlistEmpty() {
    XCTAssertEqual(
      SystemSettingsPaneMetadata.displayName(info: [:], localizedInfo: nil, fallbackStem: "SharingPref"),
      "Sharing"
    )
    XCTAssertEqual(
      SystemSettingsPaneMetadata.displayName(info: [:], localizedInfo: nil, fallbackStem: "EnergySaverPref"),
      "Battery"
    )
  }

  func testWallpaperAliasMatchesDesktopScreenSaverStem() {
    let keywords = SystemSettingsPaneMetadata.searchKeywords(
      displayName: "Wallpaper",
      bundleIdentifier: "com.apple.preference.desktopscreeneffect",
      fallbackStem: "DesktopScreenSaverPref"
    )
    XCTAssertTrue(keywords.contains { $0.caseInsensitiveCompare("wallpaper") == .orderedSame })
  }

  func testPrivacyAliasMatchesSecurityPane() {
    let keywords = SystemSettingsPaneMetadata.searchKeywords(
      displayName: "Privacy & Security",
      bundleIdentifier: "com.apple.preference.security",
      fallbackStem: "SecurityPref"
    )
    XCTAssertTrue(keywords.contains { $0.caseInsensitiveCompare("privacy") == .orderedSame })
    XCTAssertTrue(keywords.contains { $0.caseInsensitiveCompare("privacy & security") == .orderedSame })
  }

  func testFixturePanePlistFromStringsTable() {
    let fixtureInfo: [String: Any] = [:]
    let fixtureLocalized: [String: Any] = [
      "CFBundleName": "Bluetooth",
    ]
    let name = SystemSettingsPaneMetadata.displayName(
      info: fixtureInfo,
      localizedInfo: fixtureLocalized,
      fallbackStem: "BluetoothPref"
    )
    XCTAssertEqual(name, "Bluetooth")
    let keywords = SystemSettingsPaneMetadata.searchKeywords(
      displayName: name,
      bundleIdentifier: "com.apple.preferences.BluetoothPref",
      fallbackStem: "BluetoothPref"
    )
    XCTAssertTrue(keywords.contains { $0.caseInsensitiveCompare("bluetooth") == .orderedSame })
  }
}
