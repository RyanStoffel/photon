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
    shared.appIconProbeCount = 0
  }

  private func seedClipboardCapture() {
    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(500))
      let pasteboard = NSPasteboard.general
      pasteboard.clearContents()
      pasteboard.setString("Photon parity clipboard first", forType: .string)
      try? await Task.sleep(for: .milliseconds(500))
      pasteboard.clearContents()
      pasteboard.setString("Photon parity clipboard needle", forType: .string)
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
      "clipboardCaptureCount": runtime.clipboard.items.count,
      "appIconProbeCount": appIconProbeCount,
      "settings": [
        "appearance": runtime.settings.appearance.rawValue,
        "launcherHotkey": "\(launcherHotkey.keyCode):\(launcherHotkey.carbonModifiers)",
        "clipboardHotkey": "\(clipboardHotkey.keyCode):\(clipboardHotkey.carbonModifiers)",
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

  private func launcherReport(
    panel: LauncherPanel?,
    model: LauncherViewModel,
    resolvedAppIcons: Int
  ) -> [String: Any] {
    guard let panel else {
      return ["exists": false]
    }
    let frame = panel.frame
    let buttonVisible = [
      NSWindow.ButtonType.closeButton,
      .miniaturizeButton,
      .zoomButton,
    ].contains { panel.standardWindowButton($0)?.isHidden == false }

    return [
      "exists": true,
      "visible": panel.isVisible,
      "key": panel.isKeyWindow,
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
      "clipboardResultCount": model.clipboard?.results.count ?? 0,
      "clipboardSelectedIndex": model.clipboard?.selectedIndex ?? -1,
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
