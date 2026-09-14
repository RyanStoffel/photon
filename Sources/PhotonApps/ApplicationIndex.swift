import AppKit
import Foundation
import PhotonCore

public struct IndexedApplication: Hashable, Sendable {
  public let id: String
  public let name: String
  public let subtitle: String
  public let url: URL
  public let keywords: [String]
  public let icon: CommandIcon
}

public final class ApplicationIndex: @unchecked Sendable {
  private let lock = NSLock()
  private var items: [IndexedApplication] = []

  public init() {}

  public var applications: [IndexedApplication] {
    lock.lock()
    defer { lock.unlock() }
    return items
  }

  public func refresh() {
    var found: [IndexedApplication] = []
    found.reserveCapacity(128)

    let homeApps = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
    let roots = [
      URL(fileURLWithPath: "/Applications", isDirectory: true),
      URL(fileURLWithPath: "/System/Applications", isDirectory: true),
      homeApps
    ]
    for root in roots {
      collectApps(at: root, depth: 2, into: &found)
    }

    let paneRoots = [
      URL(fileURLWithPath: "/System/Library/PreferencePanes", isDirectory: true),
      URL(fileURLWithPath: "/Library/PreferencePanes", isDirectory: true),
      FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/PreferencePanes")
    ]
    for root in paneRoots {
      collectPanes(at: root, into: &found)
    }

    found.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    lock.lock()
    items = found
    lock.unlock()
  }

  private func collectApps(at root: URL, depth: Int, into found: inout [IndexedApplication]) {
    guard depth >= 0 else {
      return
    }
    let fm = FileManager.default
    guard let children = try? fm.contentsOfDirectory(
      at: root,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    ) else {
      return
    }
    for url in children {
      if url.pathExtension == "app" {
        if let app = readApp(at: url) {
          found.append(app)
        }
      } else if depth > 0 {
        collectApps(at: url, depth: depth - 1, into: &found)
      }
    }
  }

  private func collectPanes(at root: URL, into found: inout [IndexedApplication]) {
    let fm = FileManager.default
    guard let children = try? fm.contentsOfDirectory(
      at: root,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    ) else {
      return
    }
    for url in children where url.pathExtension == "prefPane" {
      if let pane = readPane(at: url) {
        found.append(pane)
      }
    }
  }

  private func readApp(at url: URL) -> IndexedApplication? {
    let bundle = Bundle(url: url)
    let name = displayName(in: bundle, fallback: url.deletingPathExtension().lastPathComponent)
    guard !name.isEmpty else {
      return nil
    }
    let identifier = bundle?.bundleIdentifier ?? url.path
    // The launcher shows the name and icon only; the path adds nothing a user needs.
    return IndexedApplication(
      id: "app:\(identifier)",
      name: name,
      subtitle: "",
      url: url,
      keywords: [identifier, url.lastPathComponent],
      icon: .fileIcon(path: url.path)
    )
  }

  private func readPane(at url: URL) -> IndexedApplication? {
    let bundle = Bundle(url: url)
    let name = displayName(in: bundle, fallback: url.deletingPathExtension().lastPathComponent)
    let identifier = bundle?.bundleIdentifier ?? url.path
    let icon = PaneIconPolicy.icon(
      forPaneAt: url,
      info: bundle?.infoDictionary ?? [:],
      fileExists: { FileManager.default.fileExists(atPath: $0) }
    )
    return IndexedApplication(
      id: "pane:\(identifier)",
      name: name,
      subtitle: "System Settings",
      url: url,
      keywords: [identifier, "settings", "preferences"],
      icon: icon
    )
  }

  private func displayName(in bundle: Bundle?, fallback: String) -> String {
    if let bundle {
      if let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, !name.isEmpty {
        return name
      }
      if let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String, !name.isEmpty {
        return name
      }
    }
    return fallback
  }
}
