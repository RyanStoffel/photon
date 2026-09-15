#if canImport(AppKit)
import Foundation
import PhotonClipboard
import XCTest

@MainActor
final class ClipboardPasteTests: XCTestCase {
  func testTrustedPastePreparesTargetAndPostsEvents() async {
    var prepared = false
    let manager = makeManager(
      trusted: true,
      injection: .posted
    )
    manager.pasteDelay = .zero
    manager.onPrepareForPaste = {
      prepared = true
    }

    let outcome = await manager.paste(.text("sentinel"))

    XCTAssertEqual(outcome, .pasted)
    XCTAssertTrue(prepared)
    XCTAssertTrue(manager.isAccessibilityTrusted)
  }

  func testUntrustedPasteDoesNotHideTargetAndReportsPermission() async {
    var prepared = false
    let manager = makeManager(
      trusted: false,
      injection: .eventCreationFailed
    )
    manager.pasteDelay = .zero
    manager.onPrepareForPaste = {
      prepared = true
    }

    let outcome = await manager.paste(.text("sentinel"))

    XCTAssertEqual(outcome, .accessibilityRequired)
    XCTAssertFalse(prepared)
    XCTAssertFalse(manager.isAccessibilityTrusted)
  }

  func testTrustedEventCreationFailureIsNotReportedAsMissingPermission() async {
    var failureReopened = false
    let manager = makeManager(
      trusted: true,
      injection: .eventCreationFailed
    )
    manager.pasteDelay = .zero
    manager.onPasteFailure = {
      failureReopened = true
    }

    let outcome = await manager.paste(.text("sentinel"))

    XCTAssertEqual(outcome, .eventInjectionFailed)
    XCTAssertTrue(failureReopened)
    XCTAssertTrue(manager.isAccessibilityTrusted)
  }

  private func makeManager(
    trusted: Bool,
    injection: ClipboardPaster.PasteInjectionResult
  ) -> ClipboardManager {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    return ClipboardManager(
      settings: ClipboardSettings(),
      directory: directory,
      accessibilityTrust: { trusted },
      pasteInjector: { injection }
    )
  }
}
#endif
