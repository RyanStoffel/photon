import AppKit
import QuickLookUI

/// Drives the shared `QLPreviewPanel` for the selected file. The launcher
/// panel forwards `QLPreviewPanelController` requests here so the panel finds
/// its data source through the responder chain; the source is also assigned
/// directly as a fallback.
@MainActor
public final class QuickLookCoordinator: NSObject {
  public private(set) var previewURL: URL?
  /// Called after the panel closes for any reason so the owner can take focus back.
  public var onDidClose: (@MainActor () -> Void)?

  public var isVisible: Bool {
    QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible
  }

  public func show(_ url: URL) {
    previewURL = url
    let panel = QLPreviewPanel.shared()
    guard let panel else {
      return
    }
    if panel.dataSource == nil {
      panel.dataSource = self
      panel.delegate = self
    }
    if !panel.isVisible {
      panel.makeKeyAndOrderFront(nil)
    }
    panel.reloadData()
  }

  public func hide() {
    guard isVisible else {
      return
    }
    QLPreviewPanel.shared().orderOut(nil)
    onDidClose?()
  }

  public func toggle(_ url: URL?) {
    if isVisible {
      hide()
    } else if let url {
      show(url)
    }
  }

  /// Keeps the preview in sync with the selection while the panel is open.
  public func update(_ url: URL?) {
    previewURL = url
    guard isVisible else {
      return
    }
    if url == nil {
      hide()
    } else {
      QLPreviewPanel.shared().reloadData()
    }
  }

  // MARK: QLPreviewPanelController (forwarded by the launcher panel)

  public func beginControl(of panel: QLPreviewPanel) {
    panel.dataSource = self
    panel.delegate = self
  }

  public func endControl(of panel: QLPreviewPanel) {
    if panel.dataSource === self {
      panel.dataSource = nil
      panel.delegate = nil
    }
    previewURL = nil
    onDidClose?()
  }
}

/// Quick Look calls its data source on the main thread; `@preconcurrency`
/// lets these main-actor methods satisfy the nonisolated protocol.
extension QuickLookCoordinator: @preconcurrency QLPreviewPanelDataSource {
  public func numberOfPreviewItems(in _: QLPreviewPanel!) -> Int {
    previewURL == nil ? 0 : 1
  }

  public func previewPanel(_: QLPreviewPanel!, previewItemAt _: Int) -> (any QLPreviewItem)! {
    previewURL.map { $0 as NSURL }
  }
}

/// Keyboard navigation while the panel is key is handled by the launcher's
/// event monitor, which sees the event before the panel does.
extension QuickLookCoordinator: QLPreviewPanelDelegate {}
