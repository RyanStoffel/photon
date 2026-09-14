import Foundation
import PhotonCore
import XCTest

final class FrecencyStoreTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)

  func testUnusedIdScoresZero() {
    let store = FrecencyStore()
    XCTAssertEqual(store.score(id: "missing", now: now), 0)
  }

  func testMoreUsesScoreHigherAtTheSameTime() {
    var few = FrecencyStore()
    var many = FrecencyStore()
    few.recordUse(id: "app", at: now)
    many.recordUse(id: "app", at: now)
    many.recordUse(id: "app", at: now)
    many.recordUse(id: "app", at: now)
    XCTAssertGreaterThan(many.score(id: "app", now: now), few.score(id: "app", now: now))
  }

  func testRecentUseOutranksStaleUseWithSameCount() {
    var recent = FrecencyStore()
    var stale = FrecencyStore()
    recent.recordUse(id: "app", at: now)
    stale.recordUse(id: "app", at: now.addingTimeInterval(-14 * 86400))
    XCTAssertGreaterThan(recent.score(id: "app", now: now), stale.score(id: "app", now: now))
  }

  func testHalfLifeHalvesTheScore() {
    var store = FrecencyStore(halfLifeDays: 7)
    store.recordUse(id: "app", at: now.addingTimeInterval(-7 * 86400))
    let fresh = FrecencyStore.score(
      record: FrecencyRecord(count: 1, lastUsed: now),
      now: now,
      halfLifeDays: 7
    )
    let aged = store.score(id: "app", now: now)
    XCTAssertEqual(aged, fresh * 0.5, accuracy: 0.0001)
  }

  func testRoundTripPersistence() throws {
    var store = FrecencyStore(halfLifeDays: 5)
    store.recordUse(id: "com.apple.Safari", at: now)
    store.recordUse(id: "com.apple.Safari", at: now.addingTimeInterval(10))

    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("photon-frecency-test-\(UUID().uuidString).json")
    try store.save(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    let loaded = FrecencyStore.load(from: url)
    XCTAssertEqual(loaded.halfLifeDays, 5)
    XCTAssertEqual(loaded.records["com.apple.Safari"]?.count, 2)
    XCTAssertEqual(
      loaded.score(id: "com.apple.Safari", now: now.addingTimeInterval(10)),
      store.score(id: "com.apple.Safari", now: now.addingTimeInterval(10)),
      accuracy: 0.0001
    )
  }

  func testLoadMissingFileReturnsEmptyStore() {
    let url = URL(fileURLWithPath: "/tmp/photon-does-not-exist-\(UUID().uuidString).json")
    let store = FrecencyStore.load(from: url, defaultHalfLifeDays: 3)
    XCTAssertEqual(store.halfLifeDays, 3)
    XCTAssertTrue(store.records.isEmpty)
  }
}
