import AppKit
import PhotonCore
import QuickLookUI

final class LauncherPanel: NSPanel {
  /// Supplies the active launcher mode so Quick Look can find its data source
  /// through the responder chain (the panel is the key window).
  var activeMode: (@MainActor () -> (any LauncherMode)?)?
  /// Intercepts navigation before SwiftUI's TextField responder consumes it.
  var keyDownHandler: ((NSEvent) -> Bool)?
  /// Starts a window drag after movement exceeds `LauncherLayout.panelDragSlop`.
  var mouseDownHandler: ((NSEvent) -> Bool)?

  private var potentialDragStart: NSPoint?

  override var canBecomeKey: Bool {
    true
  }

  override var canBecomeMain: Bool {
    false
  }

  override func sendEvent(_ event: NSEvent) {
    if event.type == .keyDown, keyDownHandler?(event) == true {
      return
    }

    if event.type == .leftMouseDown {
      let distanceFromTop = frame.height - event.locationInWindow.y
      if distanceFromTop <= LauncherLayout.searchFieldHeight,
         handleSearchFieldDragOrClick(event)
      {
        return
      }
      potentialDragStart = event.locationInWindow
    } else if event.type == .leftMouseDragged, let start = potentialDragStart {
      let delta = hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y)
      if delta >= LauncherLayout.panelDragSlop, mouseDownHandler?(event) == true {
        potentialDragStart = nil
        return
      }
    } else if event.type == .leftMouseUp {
      potentialDragStart = nil
    }

    super.sendEvent(event)
  }

  /// The search field's text view would otherwise swallow drags. Hold that
  /// mouse-down until slop decides click vs moving the panel.
  private func handleSearchFieldDragOrClick(_ down: NSEvent) -> Bool {
    let start = down.locationInWindow
    while true {
      let next = nextEvent(
        matching: [.leftMouseDragged, .leftMouseUp],
        until: Date().addingTimeInterval(0.3),
        inMode: .common,
        dequeue: true
      )
      guard let next else {
        if NSEvent.pressedMouseButtons & 1 == 0 {
          super.sendEvent(down)
          return true
        }
        continue
      }
      if next.type == .leftMouseUp {
        super.sendEvent(down)
        super.sendEvent(next)
        return true
      }
      let delta = hypot(next.locationInWindow.x - start.x, next.locationInWindow.y - start.y)
      if delta >= LauncherLayout.panelDragSlop, mouseDownHandler?(next) == true {
        return true
      }
    }
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
