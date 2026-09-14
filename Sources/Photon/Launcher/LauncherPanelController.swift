import AppKit
import PhotonClipboard
import PhotonCore
import SwiftUI

@MainActor
final class LauncherPanelController: NSObject, NSWindowDelegate {
  private let settings: SettingsStore
  private let registry: CommandRegistry
  private let frecencyURL: URL
  private let model: LauncherViewModel
  private var panel: LauncherPanel?
  private var localMonitor: Any?

  init(settings: SettingsStore, registry: CommandRegistry, frecencyURL: URL) {
    self.settings = settings
    self.registry = registry
    self.frecencyURL = frecencyURL
    model = LauncherViewModel(registry: registry, frecency: FrecencyStore.load(from: frecencyURL))
  }

  func currentFrecency() -> FrecencyStore {
    model.frecency
  }

  /// Enables clipboard mode. Call once at startup, before the panel is shown.
  func attachClipboard(_ manager: ClipboardManager) {
    let clipboard = ClipboardHistoryViewModel(manager: manager)
    clipboard.onDismiss = { [weak self] in
      self?.hide()
    }
    model.clipboard = clipboard
  }

  func preload() {
    if panel == nil {
      panel = makePanel()
    }
  }

  func toggle() {
    preload()
    guard let panel else {
      return
    }
    if panel.isVisible {
      hide()
    } else {
      show()
    }
  }

  func show() {
    preload()
    guard let panel else {
      return
    }
    model.resetForShow()
    center(panel)
    panel.orderFrontRegardless()
    panel.makeKey()
    startMonitor()
    Task {
      await registry.reloadAll()
      await model.refresh()
    }
  }

  /// Opens the panel straight into clipboard history; toggles it closed when
  /// clipboard history is already showing.
  func showClipboard() {
    preload()
    guard let panel, model.clipboard != nil else {
      return
    }
    if panel.isVisible, model.mode == .clipboard {
      hide()
      return
    }
    if !panel.isVisible {
      model.resetForShow()
      center(panel)
      panel.orderFrontRegardless()
      panel.makeKey()
      startMonitor()
    }
    model.enterClipboard(query: "")
  }

  func hide() {
    panel?.orderOut(nil)
    stopMonitor()
    persistFrecency()
  }

  func windowDidResignKey(_: Notification) {
    hide()
  }

  private func persistFrecency() {
    do {
      try model.frecency.save(to: frecencyURL)
    } catch {
      NSLog("Photon: could not save frecency: \(error)")
    }
  }

  private func makePanel() -> LauncherPanel {
    let panel = LauncherPanel(
      contentRect: NSRect(x: 0, y: 0, width: 640, height: 420),
      styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
      backing: .buffered,
      defer: false
    )
    panel.isFloatingPanel = true
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .moveToActiveSpace]
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.hidesOnDeactivate = false
    panel.animationBehavior = .none
    panel.titleVisibility = .hidden
    panel.titlebarAppearsTransparent = true
    panel.isMovableByWindowBackground = true
    panel.delegate = self

    let host = NSHostingView(rootView: LauncherView(model: model, onRun: { [weak self] in
      self?.hide()
    }))
    host.safeAreaRegions = []
    panel.contentView = host
    return panel
  }

  private func center(_ panel: NSPanel) {
    guard let screen = NSScreen.main ?? NSScreen.screens.first else {
      return
    }
    let visible = screen.visibleFrame
    let size = panel.frame.size
    let origin = NSPoint(
      x: visible.midX - size.width / 2,
      y: visible.midY - size.height / 2 + 40
    )
    panel.setFrameOrigin(origin)
  }

  private func startMonitor() {
    stopMonitor()
    localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self else {
        return event
      }
      switch model.mode {
      case .clipboard:
        return handleClipboardKey(event)
      case .commands:
        return handleCommandKey(event)
      }
    }
  }

  private func handleCommandKey(_ event: NSEvent) -> NSEvent? {
    switch event.keyCode {
    case 53:
      hide()
      return nil
    case 126:
      model.moveSelection(-1)
      return nil
    case 125:
      model.moveSelection(1)
      return nil
    case 36, 76:
      Task {
        await self.model.runSelection()
        if self.model.lastError == nil, self.model.mode == .commands {
          self.hide()
        }
      }
      return nil
    default:
      return event
    }
  }

  /// Clipboard mode: the clipboard view model owns navigation and actions.
  /// Esc, or Delete on an empty query, returns to the command list.
  private func handleClipboardKey(_ event: NSEvent) -> NSEvent? {
    guard let clipboard = model.clipboard else {
      return handleCommandKey(event)
    }
    if clipboard.handleKeyDown(event) {
      return nil
    }
    let command = event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command)
    switch event.keyCode {
    case 53:
      model.exitClipboard()
      return nil
    case 51 where !command && model.query.isEmpty:
      model.exitClipboard()
      return nil
    default:
      return event
    }
  }

  private func stopMonitor() {
    if let localMonitor {
      NSEvent.removeMonitor(localMonitor)
      self.localMonitor = nil
    }
  }
}

final class LauncherPanel: NSPanel {
  override var canBecomeKey: Bool {
    true
  }

  override var canBecomeMain: Bool {
    false
  }
}
