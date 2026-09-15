import AppKit
import Foundation

public enum FileAccessSelection: Sendable {
  case selected([URL])
  case cancelled
  case failed(String)
}

@MainActor
public protocol FileAccessPanelPresenting {
  func chooseFolders() -> FileAccessSelection
}

@MainActor
public struct SystemFileAccessPanel: FileAccessPanelPresenting {
  public init() {}

  public func chooseFolders() -> FileAccessSelection {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = true
    panel.canCreateDirectories = false
    panel.prompt = "Grant Access"
    panel.message = "Choose the folders Photon may search, such as Documents."
    let response = panel.runModal()
    if response == .cancel {
      return .cancelled
    }
    guard response == .OK, !panel.urls.isEmpty else {
      return .failed("Photon could not read the selected folders.")
    }
    return .selected(panel.urls)
  }
}

/// Persists user-selected folder access without walking protected folders or
/// triggering TCC prompts from the launcher.
@MainActor
public final class FileAccessCoordinator: ObservableObject {
  public struct Grant: Codable, Equatable, Identifiable, Sendable {
    public let path: String
    public let bookmark: Data

    public var id: String {
      path
    }
  }

  public enum Status: Equatable, Sendable {
    case idle
    case requesting
    case granted
    case cancelled
    case failed(String)
  }

  @Published public private(set) var grants: [Grant] = []
  @Published public private(set) var status: Status = .idle

  public var folders: [String] {
    grants.map(\.path)
  }

  public var statusMessage: String? {
    switch status {
    case .idle, .requesting, .granted:
      nil
    case .cancelled:
      "Folder access was cancelled. Existing grants were kept."
    case let .failed(message):
      message
    }
  }

  private let defaults: UserDefaults
  private let storageKey: String
  private var activeURLs: [URL] = []

  public init(
    defaults: UserDefaults = .standard,
    storageKey: String = "filesSecurityScopedBookmarks"
  ) {
    self.defaults = defaults
    self.storageKey = storageKey
    restore()
  }

  public func requestAccess(
    using presenter: any FileAccessPanelPresenting = SystemFileAccessPanel()
  ) {
    status = .requesting
    switch presenter.chooseFolders() {
    case let .selected(urls):
      persist(urls)
    case .cancelled:
      status = .cancelled
    case let .failed(message):
      status = .failed(message)
    }
  }

  public func remove(path: String) {
    grants.removeAll { $0.path == path }
    activeURLs.removeAll { url in
      guard url.standardizedFileURL.path == path else {
        return false
      }
      url.stopAccessingSecurityScopedResource()
      return true
    }
    save()
    status = grants.isEmpty ? .idle : .granted
  }

  private func persist(_ urls: [URL]) {
    var merged = Dictionary(uniqueKeysWithValues: grants.map { ($0.path, $0) })
    var errors: [String] = []
    for url in urls {
      let standardized = url.standardizedFileURL
      do {
        let bookmark = try standardized.bookmarkData(
          options: [.withSecurityScope],
          includingResourceValuesForKeys: nil,
          relativeTo: nil
        )
        let path = standardized.path(percentEncoded: false)
        merged[path] = Grant(path: path, bookmark: bookmark)
      } catch {
        errors.append(standardized.lastPathComponent)
      }
    }
    grants = merged.values.sorted { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }
    save()
    restoreActiveURLs()
    if errors.isEmpty, !grants.isEmpty {
      status = .granted
    } else if !errors.isEmpty {
      status = .failed("Could not save access for: \(errors.joined(separator: ", ")).")
    } else {
      status = .failed("No folders were selected.")
    }
  }

  private func restore() {
    guard let data = defaults.data(forKey: storageKey),
          let decoded = try? JSONDecoder().decode([Grant].self, from: data)
    else {
      grants = []
      return
    }
    grants = decoded
    restoreActiveURLs()
    if !grants.isEmpty {
      status = .granted
    }
  }

  private func restoreActiveURLs() {
    for url in activeURLs {
      url.stopAccessingSecurityScopedResource()
    }
    activeURLs = []
    var refreshed: [Grant] = []
    for grant in grants {
      var stale = false
      guard let url = try? URL(
        resolvingBookmarkData: grant.bookmark,
        options: [.withSecurityScope],
        relativeTo: nil,
        bookmarkDataIsStale: &stale
      ) else {
        continue
      }
      _ = url.startAccessingSecurityScopedResource()
      activeURLs.append(url)
      if stale,
         let bookmark = try? url.bookmarkData(
           options: [.withSecurityScope],
           includingResourceValuesForKeys: nil,
           relativeTo: nil
         )
      {
        refreshed.append(Grant(path: url.standardizedFileURL.path, bookmark: bookmark))
      } else {
        refreshed.append(Grant(path: url.standardizedFileURL.path, bookmark: grant.bookmark))
      }
    }
    grants = refreshed
    save()
  }

  private func save() {
    if grants.isEmpty {
      defaults.removeObject(forKey: storageKey)
    } else if let data = try? JSONEncoder().encode(grants) {
      defaults.set(data, forKey: storageKey)
    }
  }
}
