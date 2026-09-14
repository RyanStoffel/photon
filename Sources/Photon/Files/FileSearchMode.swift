import AppKit
import PhotonCore
import PhotonFiles
import QuickLookUI
import SwiftUI

/// Adapts `PhotonFiles.FileSearchController` to the launcher's mode protocol.
@MainActor
final class FileSearchMode: LauncherMode {
  let id = "files"
  let title = "Files"
  let placeholder = "Search files"
  let prefixes = ["/", "f "]
  let activationCommandID: String? = FilesProvider.searchCommandID
  let inlineProviderID: String? = "files"

  let controller: FileSearchController
  private weak var host: (any LauncherModeHost)?

  init(controller: FileSearchController) {
    self.controller = controller
  }

  var holdsFocus: Bool {
    controller.holdsFocus
  }

  func attach(host: any LauncherModeHost) {
    self.host = host
    controller.onRequestFocus = { [weak host] in
      host?.modeRequestsFocus()
    }
    controller.onRequestDismiss = { [weak host] in
      host?.modeRequestsDismiss()
    }
    controller.onRequestActivation = { [weak host] in
      host?.modeRequestsActivation()
    }
  }

  func activate(query: String) {
    controller.activate(query: query)
  }

  func update(query: String) {
    controller.update(query: query)
  }

  func deactivate() {
    controller.deactivate()
  }

  func moveSelection(_ delta: Int) {
    controller.moveSelection(delta)
  }

  func performPrimaryAction() -> Bool {
    controller.performPrimaryAction()
  }

  func handle(_ event: NSEvent) -> Bool {
    controller.handle(event)
  }

  func icon(for command: Command) -> NSImage? {
    guard let path = FilesProvider.path(forCommandID: command.id) else {
      return nil
    }
    return FileIconCache.shared.icon(forPath: path)
  }

  func makeResultsView() -> AnyView {
    AnyView(FileSearchView(controller: controller))
  }

  var acceptsPreviewPanelControl: Bool {
    true
  }

  func beginPreviewPanelControl(_ panel: QLPreviewPanel) {
    controller.quickLook.beginControl(of: panel)
  }

  func endPreviewPanelControl(_ panel: QLPreviewPanel) {
    controller.quickLook.endControl(of: panel)
  }
}
