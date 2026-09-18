import Foundation

/// Pinned note ids, stored in the supplied defaults (or `UserDefaults.standard`).
public struct NotePinStore: Equatable, Sendable {
  public static let defaultsKey = "PhotonNotesPinnedIDs"

  public var pinnedIDs: Set<String>

  public init(pinnedIDs: Set<String> = []) {
    self.pinnedIDs = pinnedIDs
  }

  public init(defaults: UserDefaults) {
    let stored = defaults.stringArray(forKey: Self.defaultsKey) ?? []
    pinnedIDs = Set(stored)
  }

  public func isPinned(_ id: String) -> Bool {
    pinnedIDs.contains(id)
  }

  public mutating func setPinned(_ pinned: Bool, id: String) {
    if pinned {
      pinnedIDs.insert(id)
    } else {
      pinnedIDs.remove(id)
    }
  }

  public mutating func toggle(_ id: String) {
    setPinned(!isPinned(id), id: id)
  }

  public func save(to defaults: UserDefaults) {
    defaults.set(Array(pinnedIDs).sorted(), forKey: Self.defaultsKey)
  }
}
