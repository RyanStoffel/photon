import Foundation

/// In-memory history with the rules the store and the UI rely on: newest first,
/// duplicates collapse into one entry, pinned items never expire.
///
/// Pure value type so the rules are unit-testable without AppKit or disk.
public struct ClipboardHistory: Equatable, Sendable {
  public enum InsertOutcome: Equatable, Sendable {
    /// A new entry was added at the top.
    case inserted
    /// Identical content already existed; that entry moved to the top instead.
    case movedToTop(UUID)
  }

  /// Newest `copiedAt` first. Pinned state does not affect this order.
  public private(set) var items: [ClipboardItem]

  public init(items: [ClipboardItem] = []) {
    self.items = items.sorted { $0.copiedAt > $1.copiedAt }
  }

  public var isEmpty: Bool {
    items.isEmpty
  }

  public var count: Int {
    items.count
  }

  public var pinnedCount: Int {
    items.lazy.filter(\.isPinned).count
  }

  public func item(id: UUID) -> ClipboardItem? {
    items.first { $0.id == id }
  }

  public func contains(contentHash: String) -> Bool {
    items.contains { $0.contentHash == contentHash }
  }

  /// Adds `item` at the top, or refreshes the existing entry with the same
  /// content hash and moves it to the top (keeping its id, pin, and creation date).
  @discardableResult
  public mutating func insert(_ item: ClipboardItem) -> InsertOutcome {
    if let index = items.firstIndex(where: { $0.contentHash == item.contentHash }) {
      var existing = items.remove(at: index)
      existing.copiedAt = max(existing.copiedAt, item.copiedAt)
      if let bundleID = item.sourceBundleID {
        existing.sourceBundleID = bundleID
        existing.sourceAppName = item.sourceAppName
      }
      items.insert(existing, at: 0)
      return .movedToTop(existing.id)
    }
    let position = items.firstIndex { $0.copiedAt <= item.copiedAt } ?? items.endIndex
    items.insert(item, at: position)
    return .inserted
  }

  /// Moves an existing item to the top with a fresh `copiedAt`. Used after the
  /// user pastes or copies it back. Returns `false` if the id is unknown.
  @discardableResult
  public mutating func touch(id: UUID, at date: Date = Date()) -> Bool {
    guard let index = items.firstIndex(where: { $0.id == id }) else {
      return false
    }
    var item = items.remove(at: index)
    item.copiedAt = max(item.copiedAt, date)
    items.insert(item, at: 0)
    return true
  }

  @discardableResult
  public mutating func setPinned(_ pinned: Bool, id: UUID) -> Bool {
    guard let index = items.firstIndex(where: { $0.id == id }) else {
      return false
    }
    items[index].isPinned = pinned
    return true
  }

  /// Returns the new pinned state, or `nil` if the id is unknown.
  @discardableResult
  public mutating func togglePin(id: UUID) -> Bool? {
    guard let index = items.firstIndex(where: { $0.id == id }) else {
      return nil
    }
    items[index].isPinned.toggle()
    return items[index].isPinned
  }

  @discardableResult
  public mutating func remove(id: UUID) -> ClipboardItem? {
    guard let index = items.firstIndex(where: { $0.id == id }) else {
      return nil
    }
    return items.remove(at: index)
  }

  /// Removes everything, pinned items included.
  @discardableResult
  public mutating func removeAll() -> [ClipboardItem] {
    let removed = items
    items.removeAll()
    return removed
  }

  /// Drops unpinned items that are older than the retention window, then the
  /// oldest unpinned items until the total is within `maxItems`. Pinned items
  /// are never removed, even if they alone exceed the limit. Returns what was dropped.
  @discardableResult
  public mutating func prune(retention: ClipboardRetention, maxItems: Int, now: Date = Date()) -> [ClipboardItem] {
    var removed: [ClipboardItem] = []

    if let cutoff = retention.cutoff(now: now) {
      let expired = items.filter { !$0.isPinned && $0.copiedAt < cutoff }
      if !expired.isEmpty {
        let expiredIDs = Set(expired.map(\.id))
        items.removeAll { expiredIDs.contains($0.id) }
        removed.append(contentsOf: expired)
      }
    }

    let limit = max(1, maxItems)
    var excess = items.count - limit
    if excess > 0 {
      var index = items.count - 1
      while excess > 0, index >= 0 {
        if !items[index].isPinned {
          removed.append(items.remove(at: index))
          excess -= 1
        }
        index -= 1
      }
    }

    return removed
  }
}
