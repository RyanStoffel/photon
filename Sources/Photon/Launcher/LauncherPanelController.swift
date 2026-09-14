import AppKit
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
          if self.model.lastError == nil {
            self.hide()
          }
        }
        return nil
      default:
        return event
      }
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
