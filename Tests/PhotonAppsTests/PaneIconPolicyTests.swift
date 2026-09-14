import Foundation
import PhotonCore
import XCTest
@testable import PhotonApps

final class PaneIconPolicyTests: XCTestCase {
  private let pane = URL(fileURLWithPath: "/System/Library/PreferencePanes/Network.prefPane", isDirectory: true)
  private let resources = "/System/Library/PreferencePanes/Network.prefPane/Contents/Resources"

  private func resolve(info: [String: Any], existing: Set<String>) -> CommandIcon {
    PaneIconPolicy.icon(forPaneAt: pane, info: info, fileExists: { existing.contains($0) })
  }

  func testDeclaredPaneIconFileIsLoadedFromDisk() {
    let icon = resolve(
      info: ["NSPrefPaneIconFile": "Network.icns"],
      existing: ["\(resources)/Network.icns"]
    )
    XCTAssertEqual(icon, .imageFile(path: "\(resources)/Network.icns"))
  }

  func testDeclaredNameWithoutExtensionTriesImageExtensions() {
    let icon = resolve(
      info: ["NSPrefPaneIconFile": "Network"],
      existing: ["\(resources)/Network.png"]
    )
    XCTAssertEqual(icon, .imageFile(path: "\(resources)/Network.png"))
  }

  func testCFBundleIconFileIsUsedWhenThePaneKeyIsMissing() {
    let icon = resolve(
      info: ["CFBundleIconFile": "PrefPaneIcon"],
      existing: ["\(resources)/PrefPaneIcon.icns"]
    )
    XCTAssertEqual(icon, .imageFile(path: "\(resources)/PrefPaneIcon.icns"))
  }

  func testPaneKeyWinsOverCFBundleIconFile() {
    let icon = resolve(
      info: ["NSPrefPaneIconFile": "Pane.icns", "CFBundleIconFile": "Bundle.icns"],
      existing: ["\(resources)/Pane.icns", "\(resources)/Bundle.icns"]
    )
    XCTAssertEqual(icon, .imageFile(path: "\(resources)/Pane.icns"))
  }

  func testDeclaredNameInsideAnAssetCatalogUsesTheBundleResource() {
    let icon = resolve(
      info: ["NSPrefPaneIconFile": "Network.icns"],
      existing: ["\(resources)/Assets.car"]
    )
    XCTAssertEqual(icon, .bundleResource(bundlePath: pane.path, name: "Network"))
  }

  func testCFBundleIconNameUsesTheAssetCatalog() {
    let icon = resolve(
      info: ["CFBundleIconName": "AppIcon"],
      existing: ["\(resources)/Assets.car"]
    )
    XCTAssertEqual(icon, .bundleResource(bundlePath: pane.path, name: "AppIcon"))
  }

  func testUndeclaredIconFallsBackToSystemSettings() {
    XCTAssertEqual(resolve(info: [:], existing: []), PaneIconPolicy.systemSettingsIcon)
    XCTAssertEqual(
      PaneIconPolicy.systemSettingsIcon,
      .application(bundleIdentifier: "com.apple.systempreferences")
    )
  }

  func testDeclaredButMissingIconFallsBackToSystemSettings() {
    let icon = resolve(info: ["NSPrefPaneIconFile": "Gone.icns", "CFBundleIconName": "Gone"], existing: [])
    XCTAssertEqual(icon, PaneIconPolicy.systemSettingsIcon)
  }

  func testBlankDeclarationsAreIgnored() {
    let icon = resolve(info: ["NSPrefPaneIconFile": "  "], existing: ["\(resources)/Assets.car"])
    XCTAssertEqual(icon, PaneIconPolicy.systemSettingsIcon)
  }

  func testCandidateFileNames() {
    XCTAssertEqual(PaneIconPolicy.candidateFileNames(for: "Network.icns"), ["Network.icns"])
    XCTAssertEqual(PaneIconPolicy.candidateFileNames(for: "Icon.PNG"), ["Icon.PNG"])
    XCTAssertEqual(
      PaneIconPolicy.candidateFileNames(for: "Network"),
      ["Network", "Network.icns", "Network.png", "Network.tiff", "Network.tif"]
    )
  }
}
