import AppKit
import Foundation

extension AppRuntime {
  func runUIScenarioIfNeeded() {
    guard let scenario = UIScenario.current else {
      return
    }
    Task { @MainActor in
      await applyUIScenario(scenario)
      await markScenarioReady()
    }
  }

  @MainActor
  private func applyUIScenario(_ scenario: UIScenario) async {
    NSApp.activate(ignoringOtherApps: true)
    switch scenario {
    case .launcherEmpty:
      await showLauncherForScreenshot(query: "")
    case let .launcherQuery(query):
      await showLauncherForScreenshot(query: query)
    case let .settings(pane):
      settings.pendingSettingsPane = pane
      openSettings()
      positionSettingsWindowForScreenshot()
    case .notes:
      seedScreenshotNoteIfNeeded()
      notes.controller.show(focus: true)
      positionNotesWindowForScreenshot()
    }
  }

  @MainActor
  private func showLauncherForScreenshot(query: String) async {
    await launcher.prepareForScreenshot(query: query)
    try? await Task.sleep(nanoseconds: 800_000_000)
  }

  @MainActor
  private func seedScreenshotNoteIfNeeded() {
    _ = notes.controller.createNote(content: UIScenarioScreenshotNote.content)
  }

  @MainActor
  private func positionSettingsWindowForScreenshot() {
    guard let window = NSApp.windows.first(where: { $0.title.contains("Settings") || $0.className.contains("Settings") })
      ?? NSApp.windows.first(where: { $0.isVisible && $0.frame.width >= 500 })
    else {
      return
    }
    UIScenarioWindowLayout.position(window, size: NSSize(width: 640, height: 480))
  }

  @MainActor
  private func positionNotesWindowForScreenshot() {
    guard let window = NSApp.windows.first(where: { $0.title == "Photon Notes" || $0.isVisible && $0.frame.width < 500 })
    else {
      return
    }
    UIScenarioWindowLayout.position(window, size: NSSize(width: 400, height: 480))
  }

  @MainActor
  private func markScenarioReady() async {
    guard let url = UIScenario.readyMarkerURL else {
      return
    }
    try? "ready".write(to: url, atomically: true, encoding: .utf8)
  }
}

enum UIScenarioScreenshotNote {
  static let content = """
  # Screenshot sample

  A short paragraph used for automated UI screenshots.

  - First bullet item
  - Second bullet item

  - [ ] Open task
  - [x] Completed task
  """
}

enum UIScenarioWindowLayout {
  @MainActor
  static func position(_ window: NSWindow, size: NSSize) {
    guard let screen = NSScreen.main ?? NSScreen.screens.first else {
      return
    }
    let visible = screen.visibleFrame
    let width = min(size.width, visible.width - 40)
    let height = min(size.height, visible.height - 40)
    let origin = NSPoint(
      x: visible.minX + (visible.width - width) / 2,
      y: visible.minY + (visible.height - height) / 2
    )
    window.setFrame(NSRect(origin: origin, size: NSSize(width: width, height: height)), display: true)
  }
}
