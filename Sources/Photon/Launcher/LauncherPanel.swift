import AppKit
import QuickLookUI

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
