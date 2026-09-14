import PhotonCore
import XCTest

final class LauncherRowTests: XCTestCase {
  func testAppRowIsNameAndIconOnly() {
    let row = LauncherRow(command: Command(
      id: "app:com.apple.Safari",
      title: "Safari",
      keywords: ["com.apple.Safari"],
      providerID: "apps",
      icon: .fileIcon(path: "/Applications/Safari.app")
    ))
    XCTAssertEqual(row.title, "Safari")
    XCTAssertNil(row.detail)
    XCTAssertEqual(row.icon, .fileIcon(path: "/Applications/Safari.app"))
    XCTAssertEqual(row.actionVerb, "Open")
  }

  func testMeaningfulSubtitleBecomesDetail() {
    let pane = LauncherRow(command: Command(
      id: "pane:x", title: "Accessibility", subtitle: "System Settings", providerID: "apps"
    ))
    XCTAssertEqual(pane.detail, "System Settings")

    let file = LauncherRow(command: Command(
      id: "file:/Users/ryan/Documents/report.pdf",
      title: "report.pdf",
      subtitle: "~/Documents",
      providerID: "files"
    ))
    XCTAssertEqual(file.detail, "~/Documents")
  }

  func testBlankSubtitleIsDropped() {
    let row = LauncherRow(command: Command(id: "x", title: "X", subtitle: "   \n ", providerID: "test"))
    XCTAssertNil(row.detail)
  }

  func testSubtitleRepeatingTheTitleIsDropped() {
    let row = LauncherRow(command: Command(id: "x", title: "Notes", subtitle: "notes", providerID: "notes"))
    XCTAssertNil(row.detail)
  }

  func testMultilinePreviewCollapsesToOneLine() {
    let row = LauncherRow(command: Command(
      id: "note:1",
      title: "Groceries",
      subtitle: "milk\n  eggs\t\tbread  ",
      providerID: "notes"
    ))
    XCTAssertEqual(row.detail, "milk eggs bread")
  }

  func testWindowCommandsRunInsteadOfOpen() {
    let row = LauncherRow(command: Command(id: "window:leftHalf", title: "Left Half", providerID: "keybinds"))
    XCTAssertEqual(row.actionVerb, "Run")
  }

  func testCalculatorRowCopies() {
    let row = LauncherRow(command: Command(id: "calculator:x", title: "1+1 → 2", providerID: "calculator"))
    XCTAssertEqual(row.actionVerb, "Copy")
  }

  func testRowIdentityFollowsTheCommand() {
    let command = Command(id: "clipboard:history", title: "Clipboard History", providerID: "clipboard")
    XCTAssertEqual(LauncherRow(command: command).id, command.id)
  }
}
