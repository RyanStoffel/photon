import AppKit
import PhotonClipboard
import PhotonCore
import QuickLookUI
import SwiftUI

@MainActor
final class LauncherPanelController: NSObject, NSWindowDelegate {
  private let settings: SettingsStore
  private let registry: CommandRegistry
  private let frecencyURL: URL
  private let model: LauncherViewModel
  private var panel: LauncherPanel?
  private var localMonitor: Any?
  /// App that was frontmost before a mode asked us to activate; restored on hide.
  private var previousApplication: NSRunningApplication?

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
    center(panel)
    panel.orderFrontRegardless()
    panel.makeKey()
    startMonitor()
    Task {
      await registry.reloadAll()
      await model.refresh()
    }
  }

  /// Shows the launcher in a fixed position with an optional query (UI screenshot harness).
  func showForScreenshot(query: String) {
    preload()
    guard let panel else {
      return
    }
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
    let panel = LauncherPanel(
      contentRect: NSRect(x: 0, y: 0, width: 640, height: 420),
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
    panel.isMovableByWindowBackground = true
    panel.delegate = self
    panel.activeMode = { [weak self] in
      self?.model.activeMode
    }

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
      switch model.session {
      case .clipboard:
        return handleClipboardKey(event)
      case .commands:
        return handle(event) ? nil : event
      }
    }
  }

  /// Returns true when the launcher consumed the key event.
  private func handle(_ event: NSEvent) -> Bool {
    if let mode = model.activeMode, mode.handle(event) {
      return true
    }
    switch event.keyCode {
    case 53:
      escape()
      return true
    case 51:
      return deleteOnEmptyQuery()
    case 126:
      model.moveSelection(-1)
      return true
    case 125:
      model.moveSelection(1)
      return true
    case 36, 76:
      runSelection()
      return true
    default:
      return false
    }
  }

  /// Escape leaves the active mode first and hides the launcher second.
  private func escape() {
    if model.activeMode != nil {
      model.exitMode()
    } else {
      hide()
    }
  }

  /// Backspace on an empty query leaves the active mode, like deleting a token.
  private func deleteOnEmptyQuery() -> Bool {
    guard model.activeMode != nil, model.query.isEmpty else {
      return false
    }
    model.exitMode()
    return true
  }

  private func runSelection() {
    Task {
      if await model.runSelection() {
        hide()
      }
    }
  }

  /// Clipboard session: the clipboard view model owns navigation and actions.
  /// Esc, or Delete on an empty query, returns to the command list.
  private func handleClipboardKey(_ event: NSEvent) -> NSEvent? {
    guard let clipboard = model.clipboard else {
      return handle(event) ? nil : event
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

final class LauncherPanel: NSPanel {
  /// Supplies the active launcher mode so Quick Look can find its data source
  /// through the responder chain (the panel is the key window).
  var activeMode: (@MainActor () -> (any LauncherMode)?)?

  override var canBecomeKey: Bool {
    true
  }

  override var canBecomeMain: Bool {
    false
  }

  /// These NSObject category methods are nonisolated; Quick Look calls them on
  /// the main thread. `self` is boxed because a nonisolated method may not
  /// capture it in a main-actor closure directly.
  override nonisolated func acceptsPreviewPanelControl(_: QLPreviewPanel!) -> Bool {
    let panel = MainActorBox(self)
    return MainActor.assumeIsolated {
      panel.value.activeMode?()?.acceptsPreviewPanelControl ?? false
    }
  }

  override nonisolated func beginPreviewPanelControl(_ previewPanel: QLPreviewPanel!) {
    let panel = MainActorBox(self)
    MainActor.assumeIsolated {
      if let previewPanel {
        panel.value.activeMode?()?.beginPreviewPanelControl(previewPanel)
      }
    }
  }

  override nonisolated func endPreviewPanelControl(_ previewPanel: QLPreviewPanel!) {
    let panel = MainActorBox(self)
    MainActor.assumeIsolated {
      if let previewPanel {
        panel.value.activeMode?()?.endPreviewPanelControl(previewPanel)
      }
    }
  }
}

/// Carries a main-actor object through a nonisolated entry point that is
/// known to run on the main thread.
private struct MainActorBox<Value>: @unchecked Sendable {
  let value: Value

  init(_ value: Value) {
    self.value = value
  }
}
