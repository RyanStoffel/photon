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
    case .launcherRecs:
      await showLauncherRecommendationsForScreenshot()
    case let .launcherQuery(query):
      await showLauncherForScreenshot(query: query)
    case .clipboardEmpty:
      await showClipboardForScreenshot()
    case .filesEmpty:
      await showFilesForScreenshot(query: "")
    case let .filesQuery(query):
      await showFilesForScreenshot(query: query)
    case let .settings(pane):
      settings.selectedPane = pane
      openSettings()
      try? await Task.sleep(nanoseconds: 1_500_000_000)
      positionSettingsWindowForScreenshot()
    case .notes:
      seedScreenshotNoteIfNeeded()
      notes.controller.show(focus: true)
      positionNotesWindowForScreenshot()
    }
    hideWindowsExceptScenario(scenario)
  }

  @MainActor
  private func hideWindowsExceptScenario(_ scenario: UIScenario) {
    var kept = Set<ObjectIdentifier>()
    for window in keptWindows(for: scenario) {
      kept.insert(ObjectIdentifier(window))
    }
    for window in NSApp.windows where window.isVisible && !kept.contains(ObjectIdentifier(window)) {
      window.orderOut(nil)
    }
  }

  @MainActor
  private func keptWindows(for scenario: UIScenario) -> [NSWindow] {
    switch scenario {
    case .launcherEmpty, .launcherQuery, .launcherRecs, .clipboardEmpty, .filesEmpty, .filesQuery:
      if let panel = launcher.panelWindowForScreenshot {
        return [panel]
      }
      return []
    case .settings:
      return NSApp.windows.filter {
        ["General", "Appearance", "Settings"].contains($0.title)
          || $0.className.contains("Settings")
      }
    case .notes:
      if let window = notes.controller.screenshotWindow {
        return [window]
      }
      return NSApp.windows.filter { $0.title == "Screenshot sample" || $0.title == "Notes" }
    }
  }

  @MainActor
  private func showLauncherForScreenshot(query: String) async {
    await launcher.prepareForScreenshot(query: query)
    try? await Task.sleep(nanoseconds: 800_000_000)
  }

  @MainActor
  private func showLauncherRecommendationsForScreenshot() async {
    await showLauncherForScreenshot(query: "")
    launcher.model.revealRecommendations()
    await launcher.model.refresh()
    try? await Task.sleep(nanoseconds: 800_000_000)
  }

  @MainActor
  private func showFilesForScreenshot(query: String) async {
    await showLauncherForScreenshot(query: "")
    if let mode = launcher.model.modes.first(where: { $0.id == "files" }) {
      launcher.model.enter(mode: mode, query: query)
    }
    let wait: UInt64 = query.isEmpty ? 400_000_000 : 2_500_000_000
    try? await Task.sleep(nanoseconds: wait)
  }

  @MainActor
  private func showClipboardForScreenshot() async {
    launcher.showClipboardForScreenshot()
    try? await Task.sleep(nanoseconds: 800_000_000)
  }

  @MainActor
  private func seedScreenshotNoteIfNeeded() {
    _ = notes.controller.createNote(content: UIScenarioScreenshotNote.content)
  }

  @MainActor
  private func positionSettingsWindowForScreenshot() {
    let settingsWindow = NSApp.windows.first { window in
      window.title.contains("Settings") || window.className.contains("Settings")
    } ?? NSApp.windows.first { $0.isVisible && $0.frame.width >= 500 }
    guard let window = settingsWindow else {
      return
    }
    UIScenarioWindowLayout.position(window, size: NSSize(width: 640, height: 480))
  }

  @MainActor
  private func positionNotesWindowForScreenshot() {
    let notesWindow = notes.controller.screenshotWindow
      ?? NSApp.windows.first { $0.title == "Screenshot sample" || $0.title == "Notes" }
    guard let window = notesWindow else {
      return
    }
    // The window's default size; anything narrower than 420 pt squeezes the sidebar below its minimum.
    UIScenarioWindowLayout.position(window, size: NSSize(width: 720, height: 480))
  }

  @MainActor
  private func markScenarioReady() async {
    if let windowURL = UIScenario.windowIDMarkerURL, let scenario = UIScenario.current {
      let window = keptWindows(for: scenario).first
      if let window {
        try? String(window.windowNumber).write(to: windowURL, atomically: true, encoding: .utf8)
      }
    }
    guard let url = UIScenario.readyMarkerURL else {
      return
    }
    try? "ready".write(to: url, atomically: true, encoding: .utf8)
  }
}

enum UIScenarioScreenshotNote {
  static let content: String = [
    "# Screenshot sample",
    "",
    "A short paragraph used for automated UI screenshots.",
    "",
    "- First bullet item",
    "- Second bullet item",
    "",
    "- [ ] Open task",
    "- [x] Completed task",
    "",
  ].joined(separator: "\n")
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
