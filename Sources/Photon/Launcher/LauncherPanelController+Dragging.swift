import AppKit
import PhotonCore

extension LauncherPanelController {
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
      isDraggingLauncher = true
      searchBarDragInitialOrigin = panel.frame.origin
      let visible = visibleFrame(for: panel)
      let guides = LauncherPosition.snapGuideXPositions(visible: visible)
      let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first
      if let screen {
        centerGuides.show(
          visibleFrame: screen.visibleFrame,
          guideXLeft: guides.left,
          guideXRight: guides.right
        )
      }
    case let .changed(translation):
      guard let initial = searchBarDragInitialOrigin else {
        return
      }
      var origin = PanelOrigin(
        x: initial.x + translation.width,
        y: initial.y - translation.height
      )
      let size = PanelSize(width: panel.frame.width, height: panel.frame.height)
      origin = LauncherPosition.clampedOrigin(origin, panelSize: size, visible: visibleFrame(for: panel))
      panel.setFrameOrigin(NSPoint(x: origin.x, y: origin.y))
    case .ended:
      centerGuides.hide()
      isDraggingLauncher = false
      searchBarDragInitialOrigin = nil
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
    }
  }
}
