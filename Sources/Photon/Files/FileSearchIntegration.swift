import Combine
import Foundation
import PhotonCore
import PhotonFiles

/// Wires the Files feature into the app: the launcher provider, the launcher
/// mode, and a live bridge from `SettingsStore` to `FileSearchSettings`.
@MainActor
final class FileSearchIntegration {
  let provider: FilesProvider
  let controller: FileSearchController
  private var cancellables: Set<AnyCancellable> = []
  private let settings: SettingsStore
  private let access: FileAccessCoordinator

  init(
    settings: SettingsStore,
    access: FileAccessCoordinator,
    registry: CommandRegistry,
    launcher: LauncherPanelController
  ) {
    self.settings = settings
    self.access = access
    var current = settings.fileSearchSettings
    current.grantedFolders = access.folders
    let engine = FileSearchEngine()
    provider = FilesProvider(engine: engine)
    provider.update(settings: current)
    controller = FileSearchController(settings: current, engine: engine)

    registry.register(provider)
    launcher.filesProvider = provider
    launcher.fileSearchController = controller
    launcher.register(mode: FileSearchMode(controller: controller))
    provider.onInlineResultsChanged = { [weak launcher] query, hasFileHits in
      guard let launcher else {
        return
      }
      if hasFileHits {
        launcher.promoteFilesMode(query: query)
      } else {
        launcher.refreshResults()
      }
    }

    // objectWillChange fires before the write lands; hop once through the run loop to read the new values.
    settings.objectWillChange
      .receive(on: RunLoop.main)
      .sink { [weak self, weak settings] _ in
        guard let self, let settings else {
          return
        }
        refreshConfiguration()
      }
      .store(in: &cancellables)
    access.$grants
      .dropFirst()
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in
        self?.refreshConfiguration()
      }
      .store(in: &cancellables)
    access.$status
      .dropFirst()
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in
        self?.refreshConfiguration()
      }
      .store(in: &cancellables)
  }

  private func apply(_ next: FileSearchSettings) {
    controller.update(settings: next, accessNotice: access.statusMessage)
    provider.update(settings: next)
  }

  func refreshConfiguration() {
    var next = settings.fileSearchSettings
    next.grantedFolders = access.folders
    apply(next)
  }
}

extension SettingsStore {
  var fileSearchSettings: FileSearchSettings {
    FileSearchSettings(
      scope: FileSearchScope(rawValue: filesSearchScope) ?? .home,
      extraFolders: filesExtraFolders,
      excludedFolders: filesExcludedFolders,
      searchContents: filesSearchContents,
      maxResults: filesMaxResults,
      defaultAction: FileDefaultAction(rawValue: filesDefaultAction) ?? .open,
      inlineResults: filesInlineResults
    )
  }
}
