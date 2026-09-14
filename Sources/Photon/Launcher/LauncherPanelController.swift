import AppKit
import Combine
import PhotonClipboard
import PhotonCore
import QuickLookUI
import SwiftUI

@MainActor
final class LauncherPanelController: NSObject, NSWindowDelegate {
  let settings: SettingsStore
  private let registry: CommandRegistry
  private let frecencyURL: URL
  let model: LauncherViewModel
  var panel: LauncherPanel?
  var localMonitor: Any?
  private var cancellables: Set<AnyCancellable> = []
  let centerGuides = LauncherCenterGuidesOverlay()
  var searchBarDragInitialOrigin: NSPoint?
  var isDraggingLauncher = false
  /// App that was frontmost before a mode asked us to activate; restored on hide.
  private var previousApplication: NSRunningApplication?

  init(settings: SettingsStore, registry: CommandRegistry, frecencyURL: URL) {
    self.settings = settings
    self.registry = registry
    self.frecencyURL = frecencyURL
    model = LauncherViewModel(registry: registry, frecency: FrecencyStore.load(from: frecencyURL))
    super.init()
    model.preferences = settings.launcherPreferences
    observe()
  }

  /// The window follows the model: `content` decides the height, the width preset the width.
  /// `@Published` emits from `willSet`, so the sinks use the incoming value, never the model's.
  private func observe() {
    model.$content
      .removeDuplicates()
      .sink { [weak self] content in
        guard let self else {
          return
        }
        resize(width: model.panelWidth, content: content)
      }
      .store(in: &cancellables)
    model.$preferences
      .map(\.width)
      .removeDuplicates()
      .sink { [weak self] width in
        guard let self else {
          return
        }
        resize(width: width.points, content: model.content)
      }
      .store(in: &cancellables)
    // objectWillChange fires before the write lands; hop once through the run loop to read the new values.
    settings.objectWillChange
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in
        guard let self else {
          return
        }
        model.preferences = settings.launcherPreferences
      }
      .store(in: &cancellables)
    settings.$launcherStoredPosition
      .removeDuplicates()
      .sink { [weak self] _ in
        guard let self, let panel, panel.isVisible, !isDraggingLauncher else {
          return
        }
        position(panel)
      }
      .store(in: &cancellables)
  }

  func currentFrecency() -> FrecencyStore {
    model.frecency
  }

  var panelWindowForScreenshot: NSWindow? {
    panel
  }

  /// Enables clipboard mode. Call once at startup, before the panel is shown.
  func attachClipboard(_ manager: ClipboardManager) {
    let clipboard = ClipboardHistoryViewModel(manager: manager)
    clipboard.onDismiss = { [weak self] in
      self?.hide()
    }
    model.clipboard = clipboard
  }

  /// Phase 2 features with their own launcher mode register here once.
  func register(mode: any LauncherMode) {
    mode.attach(host: self)
    model.register(mode: mode)
  }

  /// Re-runs the current search, for providers whose results arrive asynchronously.
  func refreshResults() {
    guard panel?.isVisible == true else {
      return
    }
    Task { await model.refresh() }
  }

  func preload() {
    if panel == nil {
      panel = makePanel()
    }
  }

  /// Resolves every provider's icons in the background so the first list draws without a stall.
  func warmIcons() {
    let frecency = model.frecency
    Task.detached(priority: .utility) { [registry] in
      let ranked = await registry.search("", frecency: frecency)
      CommandIconCache.shared.prefetch(ranked.compactMap(\.command.icon))
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
    position(panel)
    panel.orderFrontRegardless()
    panel.makeKey()
    startMonitor()
    Task {
      await registry.reloadAll()
      await model.refresh()
    }
  }

  /// Opens clipboard mode for UI screenshots (empty history in isolated data).
  func showClipboardForScreenshot() {
    showForScreenshot(query: "")
    model.enterClipboard(query: "")
  }

  /// Shows the launcher in a fixed position with an optional query (UI screenshot harness).
  func showForScreenshot(query: String) {
    preload()
    guard let panel else {
      return
    }
    panel.title = "Photon Launcher"
    model.resetForShow()
    UIScenarioWindowLayout.position(panel, size: panel.frame.size)
    panel.orderFrontRegardless()
    panel.makeKey()
    startMonitor()
    if !query.isEmpty {
      model.query = query
    }
  }

  @MainActor
  func prepareForScreenshot(query: String) async {
    await registry.reloadAll()
    showForScreenshot(query: query)
    await model.refresh()
    let deadline = Date().addingTimeInterval(10)
    while Date() < deadline, model.results.isEmpty {
      try? await Task.sleep(nanoseconds: 100_000_000)
      await model.refresh()
    }
    prefetchVisibleIcons()
    try? await Task.sleep(nanoseconds: 500_000_000)
  }

  private func prefetchVisibleIcons() {
    let icons = model.results.compactMap(\.command.icon)
    guard !icons.isEmpty else {
      return
    }
    CommandIconCache.shared.prefetch(icons)
  }

  /// Opens the panel straight into clipboard history; toggles it closed when
  /// clipboard history is already showing.
  func showClipboard() {
    preload()
    guard let panel, model.clipboard != nil else {
      return
    }
    if panel.isVisible, model.session == .clipboard {
      hide()
      return
    }
    model.resetForShow()
    position(panel)
    panel.orderFrontRegardless()
    panel.makeKey()
    startMonitor()
    model.enterClipboard(query: "")
  }

  func hide() {
    model.prepareForHide()
    panel?.orderOut(nil)
    stopMonitor()
    persistFrecency()
    restorePreviousApplication()
  }

  func windowDidResignKey(_: Notification) {
    // Another of our windows (Quick Look) may be taking key; decide once that has settled.
    Task { [weak self] in
      guard let self, let panel, panel.isVisible, !panel.isKeyWindow else {
        return
      }
      if model.activeMode?.holdsFocus == true {
        return
      }
      hide()
    }
  }

  private func persistFrecency() {
    do {
      try model.frecency.save(to: frecencyURL)
    } catch {
      NSLog("Photon: could not save frecency: \(error)")
    }
  }

  private func restorePreviousApplication() {
    guard let previousApplication else {
      return
    }
    self.previousApplication = nil
    if NSApp.isActive, !previousApplication.isTerminated {
      _ = previousApplication.activate(options: [])
    }
  }

  private func makePanel() -> LauncherPanel {
    let size = NSSize(width: model.panelWidth, height: LauncherLayout.height(for: model.content))
    let panel = LauncherPanel(
      contentRect: NSRect(origin: .zero, size: size),
      styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
      backing: .buffered,
      defer: false
    )
    panel.isFloatingPanel = true
    panel.level = .floating
    // `.canJoinAllSpaces` and `.moveToActiveSpace` are mutually exclusive; AppKit throws
    // NSInternalInconsistencyException if both are set, which aborts AppRuntime.start().
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.hidesOnDeactivate = false
    panel.animationBehavior = .none
    panel.titleVisibility = .hidden
    panel.titlebarAppearsTransparent = true
    panel.isMovableByWindowBackground = false
    panel.delegate = self
    panel.activeMode = { [weak self] in
      self?.model.activeMode
    }

    // System material behind the whole panel, clipped to the rounded shape. The window
    // shadow follows the opaque region, so the corners stay clean.
    let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
    background.material = .popover
    background.blendingMode = .behindWindow
    background.state = .active
    background.wantsLayer = true
    background.layer?.cornerRadius = LauncherLayout.cornerRadius
    background.layer?.cornerCurve = .continuous
    background.layer?.masksToBounds = true
    background.autoresizingMask = [.width, .height]

    let host = NSHostingView(rootView: LauncherView(
      model: model,
      onRun: { [weak self] in
        self?.hide()
      },
      onSearchBarDrag: { [weak self] phase in
        self?.handleSearchBarDrag(phase)
      }
    ).environmentObject(settings))
    host.safeAreaRegions = []
    host.frame = background.bounds
    host.autoresizingMask = [.width, .height]
    background.addSubview(host)
    panel.contentView = background
    return panel
  }

  /// Keeps the top edge fixed so the search field never jumps.
  /// Recentres horizontally only when snapped to center.
  private func resize(width: Double, content: LauncherContent) {
    guard let panel else {
      return
    }
    let size = NSSize(width: width, height: LauncherLayout.height(for: content))
    var frame = panel.frame
    guard frame.size != size else {
      return
    }
    let keepsCenter = settings.launcherStoredPosition?.isHorizontallyCentered ?? true
    if keepsCenter, !isDraggingLauncher {
      frame.origin.x = frame.midX - size.width / 2
    }
    frame.origin.y = frame.maxY - size.height
    frame.size = size
    // No animation: the resize and SwiftUI's relayout land in the same display cycle.
    panel.setFrame(frame, display: false, animate: false)
    panel.invalidateShadow()
  }
}

extension LauncherPanelController: LauncherModeHost {
  func modeRequestsFocus() {
    guard let panel, panel.isVisible else {
      return
    }
    panel.makeKey()
  }

  func modeRequestsDismiss() {
    hide()
  }

  func modeRequestsActivation() {
    guard !NSApp.isActive else {
      return
    }
    if previousApplication == nil {
      previousApplication = NSWorkspace.shared.frontmostApplication
    }
    NSApp.activate()
  }
}
