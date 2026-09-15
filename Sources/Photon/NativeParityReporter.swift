import AppKit
import Foundation
import PhotonCore

/// Writes live state from the packaged app for the macOS runtime parity harness.
/// It is completely inert outside CI's explicit `PHOTON_NATIVE_PARITY_REPORT_PATH`.
@MainActor
final class NativeParityReporter: NSObject {
  private static let shared = NativeParityReporter()

  static var isRequested: Bool {
    guard let path = ProcessInfo.processInfo.environment["PHOTON_NATIVE_PARITY_REPORT_PATH"] else {
      return false
    }
    return !path.isEmpty
  }

  private var runtime: AppRuntime?
  private weak var statusItemController: StatusItemController?
  private var reportURL: URL?
  private var commandURL: URL?
  private var timer: Timer?
  private var appIconProbeCount = 0

  static func startIfRequested(runtime: AppRuntime, statusItem: StatusItemController?) {
    guard isRequested,
          let path = ProcessInfo.processInfo.environment["PHOTON_NATIVE_PARITY_REPORT_PATH"]
    else {
      return
    }
    shared.runtime = runtime
    shared.statusItemController = statusItem
    shared.reportURL = URL(fileURLWithPath: path)
    if let commandPath = ProcessInfo.processInfo.environment["PHOTON_NATIVE_PARITY_COMMAND_PATH"] {
      shared.commandURL = URL(fileURLWithPath: commandPath)
    }
    shared.timer?.invalidate()
    let timer = Timer(
      timeInterval: 0.1,
      target: shared,
      selector: #selector(writeReport),
      userInfo: nil,
      repeats: true
    )
    RunLoop.main.add(timer, forMode: .common)
    shared.timer = timer
    shared.writeReport()
    shared.seedClipboardCapture()
    shared.probeApplicationIcons()
  }

  static func stop() {
    shared.timer?.invalidate()
    shared.timer = nil
    shared.runtime = nil
    shared.statusItemController = nil
    shared.reportURL = nil
    shared.commandURL = nil
    shared.appIconProbeCount = 0
  }

  private func seedClipboardCapture() {
    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(500))
      let pasteboard = NSPasteboard.general
      let longText = [
        "Photon v0.3.3 long clipboard detail sentinel.",
        "",
        "This entry proves that Photon renders the complete selected copy in the detail pane, not only the",
        "truncated row title. Keyboard selection must update this preview while the compact hotkey entry",
        "remains unchanged.",
        "",
        "Full preview tail sentinel: PHOTON-COMPLETE-TEXT-3391",
      ].joined(separator: "\n")
      for value in [
        "Photon parity clipboard alpha",
        "Photon parity clipboard bravo",
        longText,
        "Photon parity clipboard delta",
        ProcessInfo.processInfo.environment["PHOTON_NATIVE_PARITY_PASTE_SENTINEL"] ?? "Photon paste sentinel",
      ] {
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
        try? await Task.sleep(for: .milliseconds(500))
      }
      let image = NSImage(size: NSSize(width: 536, height: 440))
      image.lockFocus()
      NSColor.white.setFill()
      NSRect(origin: .zero, size: image.size).fill()
      let text = "Photon Image Detail"
      text.draw(
        at: NSPoint(x: 136, y: 205),
        withAttributes: [
          .font: NSFont.systemFont(ofSize: 28, weight: .semibold),
          .foregroundColor: NSColor.black,
        ]
      )
      image.unlockFocus()
      guard let tiff = image.tiffRepresentation else {
        return
      }
      guard let bitmap = NSBitmapImageRep(data: tiff) else {
        return
      }
      guard let png = bitmap.representation(using: .png, properties: [:]) else {
        return
      }
      pasteboard.clearContents()
      pasteboard.setData(png, forType: .png)
    }
  }

  private func probeApplicationIcons() {
    guard let runtime else {
      return
    }
    Task { @MainActor in
      await runtime.registry.reloadAll()
      let results = await runtime.registry.search("saf", frecency: runtime.launcher.model.frecency)
      appIconProbeCount = results.filter { result in
        guard result.command.providerID == "apps", let icon = result.command.icon else {
          return false
        }
        return CommandIconCache.shared.image(for: icon)?.isValid == true
      }.count
      writeReport()
    }
  }

  @objc private func writeReport() {
    guard let runtime, let reportURL else {
      return
    }
    handleCommand(runtime: runtime)
    let panel = runtime.launcher.panel
    let model = runtime.launcher.model
    let statusItem = statusItemController?.statusItem
    let appearance = panel?.effectiveAppearance ?? NSApp.effectiveAppearance
    let launcherHotkey = runtime.settings.hotkey
    let clipboardHotkey = runtime.settings.clipboardHotkey

    let resolvedAppIcons = model.results.filter { result in
      guard result.command.providerID == "apps", let icon = result.command.icon else {
        return false
      }
      return CommandIconCache.shared.image(for: icon)?.isValid == true
    }.count

    let report: [String: Any] = [
      "pid": ProcessInfo.processInfo.processIdentifier,
      "activationPolicy": NSRunningApplication.current.activationPolicy.rawValue,
      "ownsMenuBar": NSRunningApplication.current.ownsMenuBar,
      "statusItem": [
        "visible": statusItem?.isVisible == true,
        "hasButton": statusItem?.button != nil,
        "menuItemCount": statusItem?.menu?.items.count ?? 0,
        "menuTitles": statusItem?.menu?.items.map(\.title) ?? [],
      ],
      "appearance": [
        "name": appearance.bestMatch(from: [.aqua, .darkAqua])?.rawValue ?? appearance.name.rawValue,
        "controlBackground": colorComponents(.controlBackgroundColor, appearance: appearance),
        "label": colorComponents(.labelColor, appearance: appearance),
      ],
      "launcher": launcherReport(panel: panel, model: model, resolvedAppIcons: resolvedAppIcons),
      "launcherDrag": [
        "acceptedCount": runtime.launcher.acceptedChromeDragCount,
        "active": runtime.launcher.isDraggingLauncher,
        "guidesVisible": runtime.launcher.centerGuides.isVisible,
        "mouseDownCount": runtime.launcher.chromeMouseDownCount,
      ],
      "clipboardCaptureCount": runtime.clipboard.items.count,
      "clipboardAccessibilityTrusted": runtime.clipboard.isAccessibilityTrusted,
      "appIconProbeCount": appIconProbeCount,
      "settings": [
        "appearance": runtime.settings.appearance.rawValue,
        "launcherHotkey": "\(launcherHotkey.keyCode):\(launcherHotkey.carbonModifiers)",
        "clipboardHotkey": "\(clipboardHotkey.keyCode):\(clipboardHotkey.carbonModifiers)",
        "launcherPosition": launcherPositionReport(runtime.settings.launcherStoredPosition),
      ],
      "features": [
        "notesRegistered": model.results.contains { $0.command.providerID == "notes" },
        "filesModeRegistered": model.modes.contains { $0.id == "files" },
      ],
    ]

    guard JSONSerialization.isValidJSONObject(report),
          let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
    else {
      return
    }
    try? data.write(to: reportURL, options: .atomic)
  }

  private func handleCommand(runtime: AppRuntime) {
    guard let commandURL, let contents = try? String(contentsOf: commandURL, encoding: .utf8) else {
      return
    }
    let command = contents.trimmingCharacters(in: .whitespacesAndNewlines)
    try? FileManager.default.removeItem(at: commandURL)
    if command == "hideLauncher" {
      runtime.launcher.hide()
    } else if command == "showLauncher" {
      runtime.launcher.show()
    }
  }

  private func launcherReport(
    panel: LauncherPanel?,
    model: LauncherViewModel,
    resolvedAppIcons: Int
  ) -> [String: Any] {
    guard let panel else {
      return ["exists": false]
    }
    let frame = panel.frame
    let displayedTitles: [String] = if model.activeMode?.id == "files" {
      runtime?.fileSearch?.controller.results.map(\.file.displayName) ?? []
    } else if model.session == .clipboard {
      model.clipboard?.results.map(\.title) ?? []
    } else {
      model.rows.map(\.title)
    }
    let buttonVisible = [
      NSWindow.ButtonType.closeButton,
      .miniaturizeButton,
      .zoomButton,
    ].contains { panel.standardWindowButton($0)?.isHidden == false }

    return [
      "exists": true,
      "visible": panel.isVisible,
      "key": panel.isKeyWindow,
      "windowNumber": panel.windowNumber,
      "class": panel.className,
      "frame": [
        "x": frame.origin.x,
        "y": frame.origin.y,
        "width": frame.width,
        "height": frame.height,
        "top": frame.maxY,
      ],
      "styleMask": panel.styleMask.rawValue,
      "borderless": panel.styleMask.contains(.borderless),
      "nonactivatingPanel": panel.styleMask.contains(.nonactivatingPanel),
      "titled": panel.styleMask.contains(.titled),
      "floating": panel.isFloatingPanel,
      "level": panel.level.rawValue,
      "canBecomeMain": panel.canBecomeMain,
      "standardButtonVisible": buttonVisible,
      "session": model.session == .clipboard ? "clipboard" : "commands",
      "mode": model.activeMode?.id ?? "",
      "query": model.query,
      "content": contentName(model.content),
      "resultCount": model.results.count,
      "displayedRowTitles": displayedTitles,
      "fileSelectedName": runtime?.fileSearch?.controller.selected?.displayName ?? "",
      "fileSelectedType": runtime?.fileSearch?.controller.selected?.contentType ?? "",
      "clipboardResultCount": model.clipboard?.results.count ?? 0,
      "clipboardSelectedIndex": model.clipboard?.selectedIndex ?? -1,
      "clipboardSelectedTitle": model.clipboard?.selectedItem?.title ?? "",
      "clipboardSelectedKind": model.clipboard?.selectedItem?.kind.rawValue ?? "",
      "clipboardNotice": model.clipboard?.notice?.message ?? "",
      "resolvedAppIconCount": resolvedAppIcons,
    ]
  }

  private func contentName(_ content: LauncherContent) -> String {
    switch content {
    case .searchOnly:
      "searchOnly"
    case .rows:
      "rows"
    case .fullHeight:
      "fullHeight"
    }
  }

  private func launcherPositionReport(_ position: LauncherStoredPosition?) -> [String: Any] {
    guard let position else {
      return ["exists": false]
    }
    return [
      "exists": true,
      "x": position.originX,
      "y": position.originY,
      "centered": position.isHorizontallyCentered,
    ]
  }

  private func colorComponents(_ color: NSColor, appearance: NSAppearance) -> [String: Double] {
    var resolved: NSColor?
    appearance.performAsCurrentDrawingAppearance {
      resolved = color.usingColorSpace(.deviceRGB)
    }
    guard let resolved else {
      return [:]
    }
    return [
      "red": resolved.redComponent,
      "green": resolved.greenComponent,
      "blue": resolved.blueComponent,
      "alpha": resolved.alphaComponent,
    ]
  }
}
