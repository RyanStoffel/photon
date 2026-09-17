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
  /// Event numbers of re-queued search-field clicks. Stale numbers must not
  /// disable drag interception for later HID mouse-downs.
  private var passthroughEventNumbers: Set<Int> = []
  private var nextReplayEventNumber = 10_000_000

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

    if passthroughEventNumbers.remove(event.eventNumber) != nil {
      super.sendEvent(event)
      return
    }

    if event.type == .leftMouseDown {
      let distanceFromTop = frame.height - event.locationInWindow.y
      if distanceFromTop <= LauncherLayout.searchFieldHeight {
        handleSearchFieldDragOrClick(event)
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

  /// The search field's text view swallows HID drags once it sees mouse-down.
  /// Hold that click until slop decides click vs moving the panel, then either
  /// start a window drag or re-queue the click so the field can focus.
  private func handleSearchFieldDragOrClick(_ down: NSEvent) {
    let start = down.locationInWindow
    while true {
      let next = nextEvent(
        matching: [.leftMouseDragged, .leftMouseUp],
        until: Date.distantFuture,
        inMode: .eventTracking,
        dequeue: true
      )
      guard let next else {
        if NSEvent.pressedMouseButtons & 1 == 0 {
          replaySearchClick(down: down, up: nil)
          return
        }
        continue
      }
      if next.type == .leftMouseUp {
        replaySearchClick(down: down, up: next)
        return
      }
      let delta = hypot(next.locationInWindow.x - start.x, next.locationInWindow.y - start.y)
      if delta >= LauncherLayout.panelDragSlop, mouseDownHandler?(next) == true {
        return
      }
    }
  }

  /// Re-queue the click after this `sendEvent` returns. Replaying with
  /// `super.sendEvent` while the matching mouse-up is already dequeued makes
  /// the text field wait for the *next* mouse-up, which eats row clicks.
  private func replaySearchClick(down: NSEvent, up: NSEvent?) {
    if let queuedDown = copyMouseEvent(down) {
      passthroughEventNumbers.insert(queuedDown.eventNumber)
      NSApp.postEvent(queuedDown, atStart: false)
    }
    if let up, let queuedUp = copyMouseEvent(up) {
      passthroughEventNumbers.insert(queuedUp.eventNumber)
      NSApp.postEvent(queuedUp, atStart: false)
    }
  }

  private func copyMouseEvent(_ event: NSEvent) -> NSEvent? {
    nextReplayEventNumber += 1
    return NSEvent.mouseEvent(
      with: event.type,
      location: event.locationInWindow,
      modifierFlags: event.modifierFlags,
      timestamp: ProcessInfo.processInfo.systemUptime,
      windowNumber: windowNumber,
      context: nil,
      eventNumber: nextReplayEventNumber,
      clickCount: max(event.clickCount, 1),
      pressure: event.pressure
    )
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
