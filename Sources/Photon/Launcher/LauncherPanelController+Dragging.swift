import AppKit
import PhotonCore

extension LauncherPanelController {
  /// Starts a window drag from anywhere on the panel. Clicks still reach rows
  /// and buttons because `LauncherPanel` only calls this after drag slop.
  func handlePanelDrag(_: NSEvent, panel: NSPanel) -> Bool {
    chromeMouseDownCount += 1
    acceptedChromeDragCount += 1
    trackLiveDrag(panel: panel)
    return true
  }

  func handleChromeMouseDown(_ event: NSEvent, panel: NSPanel) -> Bool {
    handlePanelDrag(event, panel: panel)
  }

  func visibleFrame(for panel: NSPanel) -> ScreenVisibleFrame {
    let rect = (panel.screen ?? NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? .zero
    return ScreenVisibleFrame(
      minX: rect.minX,
      minY: rect.minY,
      width: rect.width,
      height: rect.height
    )
  }

  /// Centred horizontally by default.
  /// Uses a stored origin when the user has repositioned the panel.
  func position(_ panel: NSPanel) {
    guard panel.screen != nil || NSScreen.main != nil || !NSScreen.screens.isEmpty else {
      return
    }
    let visible = visibleFrame(for: panel)
    let size = PanelSize(width: panel.frame.width, height: panel.frame.height)
    let origin = LauncherPosition.origin(
      panelSize: size,
      visible: visible,
      stored: settings.launcherStoredPosition
    )
    panel.setFrameOrigin(NSPoint(x: origin.x, y: origin.y))
  }

  func handleSearchBarDrag(_ phase: LauncherSearchBarDragPhase) {
    guard let panel else {
      return
    }
    switch phase {
    case .began:
      trackLiveDrag(panel: panel)
    case .changed, .ended:
      break
    }
  }

  /// Follows `NSEvent.mouseLocation` until the button is released so the panel
  /// cannot fight SwiftUI's view-local drag translation.
  func trackLiveDrag(panel: NSPanel) {
    guard !isDraggingLauncher else {
      return
    }
    isDraggingLauncher = true
    let startMouse = NSEvent.mouseLocation
    let startOrigin = PanelOrigin(x: panel.frame.origin.x, y: panel.frame.origin.y)
    searchBarDragInitialOrigin = panel.frame.origin
    showCenterGuides(for: panel)

    while true {
      let event = panel.nextEvent(
        matching: [.leftMouseDragged, .leftMouseUp],
        until: Date.distantFuture,
        inMode: .eventTracking,
        dequeue: true
      )
      applyLiveDragOrigin(
        panel: panel,
        startOrigin: startOrigin,
        startMouse: startMouse,
        currentMouse: NSEvent.mouseLocation
      )
      if event == nil || event?.type == .leftMouseUp {
        break
      }
    }

    finishLiveDrag(panel: panel)
  }

  func showCenterGuides(for panel: NSPanel) {
    let visible = visibleFrame(for: panel)
    let guides = LauncherPosition.snapGuideXPositions(
      visible: visible,
      panelWidth: panel.frame.width
    )
    let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first
    if let screen {
      centerGuides.show(
        visibleFrame: screen.visibleFrame,
        guideXLeft: guides.left,
        guideXRight: guides.right
      )
    }
  }

  func applyLiveDragOrigin(
    panel: NSPanel,
    startOrigin: PanelOrigin,
    startMouse: NSPoint,
    currentMouse: NSPoint
  ) {
    let visible = visibleFrame(for: panel)
    let size = PanelSize(width: panel.frame.width, height: panel.frame.height)
    var origin = LauncherPosition.liveDragOrigin(
      initialOrigin: startOrigin,
      startMouse: PanelOrigin(x: startMouse.x, y: startMouse.y),
      currentMouse: PanelOrigin(x: currentMouse.x, y: currentMouse.y),
      panelWidth: size.width,
      visible: visible
    )
    origin = LauncherPosition.clampedOrigin(origin, panelSize: size, visible: visible)
    panel.setFrameOrigin(NSPoint(x: origin.x, y: origin.y))
  }

  func finishLiveDrag(panel: NSPanel) {
    centerGuides.hide()
    let size = PanelSize(width: panel.frame.width, height: panel.frame.height)
    let origin = PanelOrigin(x: panel.frame.origin.x, y: panel.frame.origin.y)
    let stored = LauncherPosition.storedPosition(
      origin: origin,
      panelWidth: size.width,
      visible: visibleFrame(for: panel)
    )
    settings.launcherStoredPosition = stored
    var frame = panel.frame
    frame.origin.x = stored.originX
    frame.origin.y = stored.originY
    panel.setFrame(frame, display: false, animate: false)
    searchBarDragInitialOrigin = nil
    isDraggingLauncher = false
  }
}
