import Foundation
import PhotonClipboard
import XCTest

final class ClipboardHistoryTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)

  private func text(_ value: String, minutesAgo: Double = 0, pinned: Bool = false) -> ClipboardItem {
    ClipboardItem.text(value, at: now.addingTimeInterval(-minutesAgo * 60), isPinned: pinned)
  }

  // MARK: Ordering

  func testInitSortsNewestFirst() {
    let history = ClipboardHistory(items: [text("old", minutesAgo: 30), text("new"), text("mid", minutesAgo: 10)])
    XCTAssertEqual(history.items.map(\.text), ["new", "mid", "old"])
  }

  func testInsertPutsNewestOnTop() {
    var history = ClipboardHistory()
    history.insert(text("first", minutesAgo: 2))
    history.insert(text("second", minutesAgo: 1))
    XCTAssertEqual(history.items.map(\.text), ["second", "first"])
  }

  // MARK: Dedupe

  func testConsecutiveIdenticalCopiesCollapseIntoOneEntry() {
    var history = ClipboardHistory()
    let first = text("same", minutesAgo: 5)
    XCTAssertEqual(history.insert(first), .inserted)
    XCTAssertEqual(history.insert(text("same")), .movedToTop(first.id))
    XCTAssertEqual(history.count, 1)
    XCTAssertEqual(history.items[0].id, first.id)
    XCTAssertEqual(history.items[0].copiedAt, now)
    XCTAssertEqual(history.items[0].createdAt, now.addingTimeInterval(-300))
  }

  func testDuplicateDeeperInHistoryMovesToTop() {
    var history = ClipboardHistory()
    let alpha = text("alpha", minutesAgo: 3)
    history.insert(alpha)
    history.insert(text("beta", minutesAgo: 2))
    history.insert(text("gamma", minutesAgo: 1))
    XCTAssertEqual(history.insert(text("alpha")), .movedToTop(alpha.id))
    XCTAssertEqual(history.items.map(\.text), ["alpha", "gamma", "beta"])
    XCTAssertEqual(history.count, 3)
  }

  func testDedupeKeepsPinAndUpdatesSourceApp() {
    var history = ClipboardHistory()
    var pinned = text("keep me", minutesAgo: 10, pinned: true)
    pinned.sourceBundleID = "com.apple.Notes"
    history.insert(pinned)
    history.insert(text("other", minutesAgo: 5))
    var again = text("keep me")
    again.sourceBundleID = "com.apple.Safari"
    again.sourceAppName = "Safari"
    history.insert(again)
    XCTAssertEqual(history.count, 2)
    XCTAssertTrue(history.items[0].isPinned)
    XCTAssertEqual(history.items[0].id, pinned.id)
    XCTAssertEqual(history.items[0].sourceBundleID, "com.apple.Safari")
    XCTAssertEqual(history.items[0].sourceAppName, "Safari")
  }

  func testDifferentContentIsNotDeduped() {
    var history = ClipboardHistory()
    history.insert(text("hello"))
    history.insert(text("hello "))
    history.insert(text("Hello"))
    XCTAssertEqual(history.count, 3)
  }

  func testImageAndFileHashesAreStableAndDistinct() {
    let png = Data([0x89, 0x50, 0x4e, 0x47, 0x01, 0x02])
    XCTAssertEqual(ClipboardContent.hash(imageData: png), ClipboardContent.hash(imageData: png))
    XCTAssertNotEqual(ClipboardContent.hash(imageData: png), ClipboardContent.hash(imageData: Data([0x00])))
    XCTAssertEqual(
      ClipboardContent.hash(filePaths: ["/a", "/b"]),
      ClipboardContent.hash(filePaths: ["/b", "/a"]),
      "file sets hash independent of order"
    )
    XCTAssertNotEqual(ClipboardContent.hash(text: "/a"), ClipboardContent.hash(filePaths: ["/a"]))
  }

  // MARK: Touch, pin, remove

  func testTouchMovesItemToTop() {
    var history = ClipboardHistory()
    let old = text("old", minutesAgo: 10)
    history.insert(old)
    history.insert(text("new"))
    XCTAssertTrue(history.touch(id: old.id, at: now.addingTimeInterval(5)))
    XCTAssertEqual(history.items[0].id, old.id)
    XCTAssertFalse(history.touch(id: UUID()))
  }

  func testTogglePin() {
    var history = ClipboardHistory()
    let item = text("pin")
    history.insert(item)
    XCTAssertEqual(history.togglePin(id: item.id), true)
    XCTAssertEqual(history.pinnedCount, 1)
    XCTAssertEqual(history.togglePin(id: item.id), false)
    XCTAssertNil(history.togglePin(id: UUID()))
  }

  func testRemoveAndRemoveAll() {
    var history = ClipboardHistory()
    let a = text("a", minutesAgo: 1)
    history.insert(a)
    history.insert(text("b", pinned: true))
    XCTAssertEqual(history.remove(id: a.id)?.text, "a")
    XCTAssertNil(history.remove(id: a.id))
    XCTAssertEqual(history.removeAll().count, 1)
    XCTAssertTrue(history.isEmpty)
  }

  // MARK: Retention

  func testRetentionDropsOldUnpinnedItemsOnly() {
    var history = ClipboardHistory()
    let stale = text("stale", minutesAgo: 8 * 24 * 60)
    let stalePinned = text("stale pinned", minutesAgo: 9 * 24 * 60, pinned: true)
    let fresh = text("fresh", minutesAgo: 60)
    history.insert(stale)
    history.insert(stalePinned)
    history.insert(fresh)

    let removed = history.prune(retention: .sevenDays, maxItems: 100, now: now)
    XCTAssertEqual(removed.map(\.id), [stale.id])
    XCTAssertEqual(Set(history.items.map(\.id)), [stalePinned.id, fresh.id])
  }

  func testForeverKeepsEverything() {
    var history = ClipboardHistory()
    history.insert(text("ancient", minutesAgo: 400 * 24 * 60))
    XCTAssertTrue(history.prune(retention: .forever, maxItems: 100, now: now).isEmpty)
    XCTAssertEqual(history.count, 1)
  }

  func testOneDayCutoffIsExact() {
    var history = ClipboardHistory()
    let justInside = text("inside", minutesAgo: 23 * 60 + 59)
    let justOutside = text("outside", minutesAgo: 24 * 60 + 1)
    history.insert(justInside)
    history.insert(justOutside)
    let removed = history.prune(retention: .oneDay, maxItems: 100, now: now)
    XCTAssertEqual(removed.map(\.id), [justOutside.id])
  }

  func testMaxItemsDropsOldestUnpinnedFirst() {
    var history = ClipboardHistory()
    let items = (0 ..< 6).map { text("item \($0)", minutesAgo: Double($0)) }
    for item in items {
      history.insert(item)
    }
    history.setPinned(true, id: items[5].id)

    let removed = history.prune(retention: .forever, maxItems: 4, now: now)
    XCTAssertEqual(Set(removed.map(\.id)), [items[3].id, items[4].id])
    XCTAssertEqual(history.count, 4)
    XCTAssertTrue(history.items.contains { $0.id == items[5].id }, "pinned oldest item survives the limit")
  }

  func testPinnedItemsAloneMayExceedMaxItems() {
    var history = ClipboardHistory()
    for index in 0 ..< 5 {
      history.insert(text("pinned \(index)", minutesAgo: Double(index), pinned: true))
    }
    history.insert(text("loose", minutesAgo: 10))
    let removed = history.prune(retention: .forever, maxItems: 2, now: now)
    XCTAssertEqual(removed.map(\.text), ["loose"])
    XCTAssertEqual(history.count, 5)
  }

  func testRetentionFromDaysMapsToCases() {
    XCTAssertEqual(ClipboardRetention(days: 1), .oneDay)
    XCTAssertEqual(ClipboardRetention(days: 7), .sevenDays)
    XCTAssertEqual(ClipboardRetention(days: 30), .thirtyDays)
    XCTAssertEqual(ClipboardRetention(days: 0), .forever)
    XCTAssertEqual(ClipboardRetention(days: 12), .thirtyDays, "unknown values fall back to the default")
    XCTAssertNil(ClipboardRetention.forever.cutoff(now: now))
    XCTAssertEqual(ClipboardRetention.oneDay.cutoff(now: now), now.addingTimeInterval(-86400))
  }

  // MARK: Settings

  func testExcludedBundleIDsAreCaseInsensitive() {
    let settings = ClipboardSettings(excludedBundleIDs: ["com.1password.1password"])
    XCTAssertTrue(settings.isExcluded(bundleID: "com.1Password.1Password"))
    XCTAssertFalse(settings.isExcluded(bundleID: "com.apple.Safari"))
    XCTAssertFalse(settings.isExcluded(bundleID: nil))
  }

  func testDefaultExclusionsCoverPasswordManagers() {
    let settings = ClipboardSettings()
    XCTAssertTrue(settings.isExcluded(bundleID: "com.1password.1password"))
    XCTAssertTrue(settings.isExcluded(bundleID: "com.bitwarden.desktop"))
    XCTAssertTrue(settings.isExcluded(bundleID: "com.apple.keychainaccess"))
    XCTAssertTrue(settings.isExcluded(bundleID: "org.keepassxc.keepassxc"))
  }
}
