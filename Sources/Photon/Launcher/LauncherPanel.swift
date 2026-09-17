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
  private var searchBarDragStart: NSPoint?
  private var searchBarDragMonitor: Any?

  override var canBecomeKey: Bool {
    true
  }

  override var canBecomeMain: Bool {
    false
  }

  func installSearchBarDragMonitor() {
    guard searchBarDragMonitor == nil else {
      return
    }
    searchBarDragMonitor = NSEvent.addLocalMonitorForEvents(
      matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp],
      handler: { [weak self] event in
        guard let panel = self else {
          return event
        }
        return panel.handleSearchBarMonitor(event)
      }
    )
  }

  override func sendEvent(_ event: NSEvent) {
    if event.type == .keyDown, keyDownHandler?(event) == true {
      return
    }

    if event.type == .leftMouseDown {
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

  /// Search-field mouse-down reaches the text view (and often a field editor)
  /// which dequeues drags before `sendEvent` sees them. A local monitor still
  /// observes those HID events in screen space so the panel can move.
  private func handleSearchBarMonitor(_ event: NSEvent) -> NSEvent? {
    switch event.type {
    case .leftMouseDown:
      searchBarDragStart = isInSearchBarBand ? NSEvent.mouseLocation : nil
    case .leftMouseDragged:
      if let start = searchBarDragStart {
        let mouse = NSEvent.mouseLocation
        let delta = hypot(mouse.x - start.x, mouse.y - start.y)
        if delta >= LauncherLayout.panelDragSlop, mouseDownHandler?(event) == true {
          searchBarDragStart = nil
          return nil
        }
      }
    case .leftMouseUp:
      searchBarDragStart = nil
    default:
      break
    }
    return event
  }

  private var isInSearchBarBand: Bool {
    let mouse = NSEvent.mouseLocation
    guard frame.contains(mouse) else {
      return false
    }
    let distanceFromTop = frame.maxY - mouse.y
    return distanceFromTop >= 0 && distanceFromTop <= LauncherLayout.searchFieldHeight
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
