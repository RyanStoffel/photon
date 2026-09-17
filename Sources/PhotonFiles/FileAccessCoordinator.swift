import AppKit
import Foundation

public enum FileAccessSelection: Sendable {
  case selected([URL])
  case cancelled
  case failed(String)
}

@MainActor
public protocol FileAccessPanelPresenting {
  func chooseFolders(parent: NSWindow?, directory: URL?) -> FileAccessSelection
}

@MainActor
public struct SystemFileAccessPanel: FileAccessPanelPresenting {
  public init() {}

  public func chooseFolders(parent: NSWindow?, directory: URL?) -> FileAccessSelection {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = true
    panel.canCreateDirectories = false
    panel.prompt = "Grant Access"
    panel.message = "Choose the folders Photon may search, such as Documents, Desktop, or Downloads."
    if let directory {
      panel.directoryURL = directory
    }
    let response = present(panel, parent: parent)
    if response == .cancel {
      return .cancelled
    }
    guard response == .OK, !panel.urls.isEmpty else {
      return .failed("Photon could not read the selected folders.")
    }
    return .selected(panel.urls)
  }

  /// Sheets attach to a visible Files window so Photon never has to hide first.
  private func present(_ panel: NSOpenPanel, parent: NSWindow?) -> NSApplication.ModalResponse {
    guard let parent, parent.isVisible else {
      return panel.runModal()
    }
    var response: NSApplication.ModalResponse?
    panel.beginSheetModal(for: parent) { result in
      response = result
    }
    while response == nil {
      RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }
    return response ?? .cancel
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
  /// True while an open panel or sequential grant is on screen.
  @Published public private(set) var isRequestingAccess = false

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
    using presenter: any FileAccessPanelPresenting = SystemFileAccessPanel(),
    parent: NSWindow? = nil,
    directory: URL? = nil
  ) {
    isRequestingAccess = true
    status = .requesting
    defer { isRequestingAccess = false }
    switch presenter.chooseFolders(parent: parent, directory: directory) {
    case let .selected(urls):
      persist(urls)
    case .cancelled:
      status = .cancelled
    case let .failed(message):
      status = .failed(message)
    }
  }

  /// Presents one folder picker per remaining suggested URL so macOS can show
  /// a single grant dialog at a time while Photon stays visible.
  @discardableResult
  public func requestAccessSequentially(
    suggestedFolders: [URL],
    using presenter: any FileAccessPanelPresenting = SystemFileAccessPanel(),
    parent: NSWindow? = nil
  ) -> Int {
    let remaining = suggestedFolders.filter { url in
      let path = url.standardizedFileURL.path(percentEncoded: false)
      return !grants.contains { $0.path == path }
    }
    guard !remaining.isEmpty else {
      requestAccess(using: presenter, parent: parent)
      return grants.count
    }
    isRequestingAccess = true
    status = .requesting
    defer { isRequestingAccess = false }
    let before = grants.count
    for url in remaining {
      switch presenter.chooseFolders(parent: parent, directory: url) {
      case let .selected(urls):
        persist(urls)
      case .cancelled:
        status = .cancelled
        return grants.count - before
      case let .failed(message):
        status = .failed(message)
        return grants.count - before
      }
    }
    return grants.count - before
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
      let refreshedBookmark = try? url.bookmarkData(
        options: [.withSecurityScope],
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )
      if stale, let bookmark = refreshedBookmark {
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
