import Combine
import PhotonCore
import PhotonFiles

/// Wires the Files feature into the app: the launcher provider, the launcher
/// mode, and a live bridge from `SettingsStore` to `FileSearchSettings`.
@MainActor
final class FileSearchIntegration {
  let provider: FilesProvider
  let controller: FileSearchController
  private var cancellable: AnyCancellable?

  init(settings: SettingsStore, registry: CommandRegistry, launcher: LauncherPanelController) {
    let current = settings.fileSearchSettings
    provider = FilesProvider()
    provider.update(settings: current)
    controller = FileSearchController(settings: current)

    registry.register(provider)
    launcher.register(mode: FileSearchMode(controller: controller))
    provider.onInlineResultsChanged = { [weak launcher] in
      launcher?.refreshResults()
    }

    // objectWillChange fires before the write lands; hop once through the run loop to read the new values.
    cancellable = settings.objectWillChange
      .receive(on: RunLoop.main)
      .sink { [weak self, weak settings] _ in
        guard let self, let settings else {
          return
        }
        apply(settings.fileSearchSettings)
      }
  }

  private func apply(_ next: FileSearchSettings) {
    guard next != controller.settings else {
      return
    }
    controller.settings = next
    provider.update(settings: next)
  }
}

extension SettingsStore {
  var fileSearchSettings: FileSearchSettings {
    FileSearchSettings(
      scope: FileSearchScope(rawValue: filesSearchScope) ?? .computer,
      extraFolders: filesExtraFolders,
      excludedFolders: filesExcludedFolders,
      searchContents: filesSearchContents,
      maxResults: filesMaxResults,
      defaultAction: FileDefaultAction(rawValue: filesDefaultAction) ?? .open,
      inlineResults: filesInlineResults
    )
  }
}
